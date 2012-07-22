package IRC::Server::Pluggable::IRCSock;
our $VERSION = '0.01';

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use MooX::Types::MooseLike::Base qw/:all/;

use POE qw/
  Session

  Wheel::SocketFactory

  Component::SSLify
  
  Filter::Stackable
  Filter::IRCD
  Filter::Line
/;

use Socket qw/
  inet_ntoa
  unpack_sockaddr_in
/;

use Try::Tiny;

has 'controller' => (
  lazy => 1,

  is   => 'ro',

  writer    => 'set_controller',
  predicate => 'has_controller',
);

has 'filter_irc' => (
  lazy => 1,

  is  => 'rwp',

  default => sub {
    POE::Filter::IRCD->new(
      colonify => 1,
    )
  },
);

has 'filter_line' => (
  lazy => 1,

  is  => 'rwp',

  default => sub {
    POE::Filter::Line->new(
      InputRegexp   => '\015?\012',
      OutputLiteral => "\015\012",
    )
  },
);

has 'filter' => (
  lazy => 1,

  is  => 'rwp',

  default => sub {
    POE::Filter::Stackable->new(
      Filters => [
        $self->filter_line,
        $self->filter_irc
      ],
    );
  },
);

has 'listeners' => (
  lazy => 1,

  is  => 'rwp',
  isa => HashRef,

  default => sub { {} },
);

has 'connectors' => (
  lazy => 1,

  is  => 'rwp',
  isa => HashRef,

  default => sub { {} },
);

has 'wheels' => (
  lazy => 1,
  
  is  => 'rwp',
  isa => HashRef,
  
  default => sub { {} },
); 


sub spawn {
  ## FIXME spawn session
}


sub _start {

}

sub _stop {
  ## decrease refcount on recorded sender if we have one
}

sub ready {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  ## FIXME
  ##  receive event from sender session
  ##  record sender id to dispatch to
  ##  increase refcount on sender
  ##  start listeners
  $self->set_controller( $_[SENDER]->ID );
}

sub p_accept_conn {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($socket, $p_addr, $p_port, $listener_id) = @_[ARG0 .. ARG3];


}

sub p_accept_fail {

}


sub create_listener {
  my $self = shift;
  $self->yield('create_listener', @_)
  1
}

sub _create_listener {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  my %args = @_[ARG0 .. $#_];

  $args{lc $_} = delete $args{$_} for keys %args;

  my $bindaddr  = delete $args{bindaddr} || '0.0.0.0';
  my $bindport  = delete $args{port}     || 0;
  my $idle_time = delete $args{idle}     || 180;

  my $ssl = delete $args{ssl} || 0;

  my $wheel = POE::Wheel::SocketFactory->new(
    BindAddress => $bindaddr,
    BindPort    => $bindport,
    SuccessEvent => 'p_accept_conn',
    FailureEvent => 'p_accept_fail',
    Reuse  => 1,
  );

  my $id = $wheel->ID;

  $self->listeners->{$id} = {
    wheel => $wheel,

    addr  => $bindaddr,
    port  => $bindport,

    idle  => $idle_time,

    ssl   => $ssl,
  };

  ## Real bound port/addr
  my ($port, $addr) = unpack_sockaddr_in( $wheel->getsockname ); 
  $self->listeners->{$id}->{port} = $port if $port;

  ## Tell our controller session
  ##  Event: listener_added $addr, $port, $wheel_id
  $kernel->post( $self->controller, 'listener_created',
    $addr, $port, $id
  );
}

sub remove_listener {
  my $self = shift;
  $self->yield( 'remove_listener', @_ );
  1
}

sub _remove_listener {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my %args = @_[ARG0 .. $#_];

  $args{lc $_} = delete $args{$_} for keys %args;

  ## FIXME delete listeners by listener ID or by port
}

sub create_connector {
  my $self = shift;
  $self->yield( 'create_connector', @_ );
  1
}

sub _create_connector {
  my ($kernel, $self) = @_;
  my %args = @_[ARG0 .. $#_];

  $args{lc $_} = delete $args{$_} for keys %args;

  my $remote_addr = $args{remoteaddr};
  my $remote_port = $args{remoteport};

  confess "_create_connector expects a RemoteAddr and RemotePort"
    unless defined $remote_addr and defined $remote_port;

  my $wheel = POE::Wheel::SocketFactory->new(
    SocketProtocol => 'tcp',
    RemoteAddress  => $remote_addr,
    RemotePort     => $remote_port,
    SuccessEvent   => '_ircsock_up',
    FailureEvent   => '_ircsock_failed',
    (defined $args{bindaddr} ? (BindAddress => $args{bindaddr}) : ()),
  );

  my $id = $wheel->ID;
  
  $self->connectors->{$id} = {
    wheel => $wheel,
    addr  => $remote_addr,
    port  => $remote_port,
    (defined $args{bindaddr} ? (bindaddr => $args{bindaddr}) : () ),
  };
}


sub _ircsock_up {
  ## Created connector socket.
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($sock, $peeraddr, $peerport, $c_id) = @_[ARG0 .. ARG3];

  $peeraddr = inet_ntoa($peeraddr);

  my $ct = delete $self->connectors->{$c_id};

  if ($ct->{ssl}) {
    try {
      $sock = POE::Component::SSLify::Client_SSLify($sock)
    } catch {
      warn "Could not SSLify (client) socket: $_";
      undef
    } or return;
  }

  my $wheel = POE::Wheel::ReadWrite->new(
    Handle       => $sock,
    InputEvent   => '_ircsock_input',
    ErrorEvent   => '_ircsock_error',
    FlushedEvent => '_ircsock_flushed',
    Filter       => POE::Filter::Stackable->new(
      Filters => [ $self->filter ],
    );
  );

  my $w_id = $wheel->ID;

  my $sockaddr = inet_ntoa( 
    ( unpack_sockaddr_in(getsockname $sock) )[1] 
  );
  my $sockport = ( unpack_sockaddr_in(getsockname $sock) )[0];

  my $ref = {
    wheel => $wheel,
    peeraddr => $peeraddr,
    peerport => $peerport,
    sockaddr => $sockaddr,
    sockport => $sockport,
    ## FIXME idle / compression ?
  };
  
  $self->wheels->{$w_id} = $ref;
  
  $kernel->post( $self->controller, 'client_connected',
    $w_id, $peeraddr, $peerport, $sockaddr, $sockport
  );
}

sub _ircsock_failed {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($op, $errno, $errstr, $c_id) = @_[ARG0 .. ARG3];

  my $ct = delete $self->connectors->{$c_id};  
  delete $ct->{wheel};

  $kernel->post( $self->controller, 'socketerr',
    $ct, $op, $errno, $errstr
  );
}

sub _ircsock_input {
  ## Input handler.
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($input, $w_id)  = @_[ARG0, ARG1];

  my $this_conn = $self->wheels->{$w_id};

  ## FIXME raw events?
  ## FIXME idle adjust?
  ## FIXME anti-flood code or should that be higher up ... ?

  ## Filter returns:
  ##  prefix  =>
  ##  command =>
  ##  params  =>
  ##  raw_line =>
  my $event = $input->{command};

  $kernel->post( $self->controller, 'irc_ev_'.$command, $input );
}

sub _ircsock_error {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($errstr, $w_id) = @_[ARG2, ARG3];
  
  ## FIXME return if no such connection
  ## FIXME otherwise call disconnected event
}

sub _ircsock_flushed {
  my ($kernel, $self, $w_id) = @_[KERNEL, OBJECT, ARG0];

  ## FIXME
  ## return if no such connection
  ## otherwise if this wheel is in a disconnecting state,
  ##  issue a disconnected event
  ## compression todo:
  ##  if this wheel has had compression requested, 
  ##   add zlib filter and send compressed_link event

}

1
