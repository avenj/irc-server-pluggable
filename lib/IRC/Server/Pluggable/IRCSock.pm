package IRC::Server::Pluggable::IRCSock;
our $VERSION = '0.01';

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable::Types;

use IRC::Server::Pluggable::IRCSock::Listener;
#use IRC::Server::Pluggable::IRCSock::Connector;

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


has 'session_id' => (
  ## Session ID for own session.
  lazy => 1,
  
  is => 'ro',
  
  writer    => 'set_session_id',
  predicate => 'has_session_id',
);

has 'controller' => (
  ## Session ID for controller session
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
    my ($self) = @_;

    POE::Filter::Stackable->new(
      Filters => [
        $self->filter_line,
        $self->filter_irc
      ],
    );
  },
);

## IRC::Server::Pluggable::IRCSock::Listener objs
has 'listeners' => (
  lazy => 1,

  is  => 'rwp',
  isa => HashRef,

  default => sub { {} },
);

## IRC::Server::Pluggable::IRCSock::Connector objs
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
  my ($class, %args) = @_;

  $args{lc $_} = delete $args{$_} for keys %args;
  
  my $self = $class->new;

  my $sess_id = POE::Session->create(
    object_states => [
      $self => {
        '_start' => '_start',
        '_stop'  => '_stop',
        
        ## FIXME
      },
    ],
  )->ID;
  
  confess "Unable to spawn POE::Session and retrieve ID()"
    unless $sess_id;

  $self->set_session_id( $sess_id );
  
  $self
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

sub _accept_conn {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($sock, $p_addr, $p_port, $listener_id) = @_[ARG0 .. ARG3];

  ## Accepted connection to a listener.

  my $sockaddr = inet_ntoa( 
    ( unpack_sockaddr_in(getsockname $sock) )[1]
  );

  my $sockport = ( unpack_sockaddr_in(getsockname $sock) )[0];
  
  $p_addr = inet_ntoa( $p_addr );
  
  my $listener = $self->listeners->{$listener_id};
  
  if ( $listener->ssl ) {
    try {
      $sock = POE::Component::SSLify::Client_SSLify($sock)
    } catch {
      warn "Could not SSLify (server) socket: $_";
      undef
    } or return;
  }
  
  my $wheel = POE::Wheel::ReadWrite->new(
    Handle => $sock,
    Filter => $self->filter,
    InputEvent => '_ircsock_input',
    ErrorEvent => '_ircsock_error',
    FlushedEvent => '_ircsock_flushed',
  );
  
  my $w_id = $wheel->ID;

  $self->wheels->{$w_id} = {
    wheel    => $wheel,
    peeraddr => $p_addr,
    peerport => $p_port,
    sockaddr => $sockaddr,
    sockport => $sockport,
  };
  

  $kernel->post( $self->controller,
    'ircsock_client_connected',
    ## FIXME
  );
}

sub _accept_fail {

}


sub create_listener {
  my $self = shift;

  $poe_kernel->post( $self->session_id,
    'create_listener', 
    @_
  );

  1
}

sub _create_listener {
  ## Create a listener on a particular port.
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
    SuccessEvent => '_accept_conn',
    FailureEvent => '_accept_fail',
    Reuse  => 1,
  );

  my $id = $wheel->ID;

  $self->listeners->{$id} = IRC::Server::Pluggable::IRCSock::Listener->new(
    wheel => $wheel,
    addr  => $bindaddr,
    port  => $bindport,
    idle  => $idle_time,
    ssl   => $ssl,
  );

  ## Real bound port/addr
  my ($port, $addr) = unpack_sockaddr_in( $wheel->getsockname ); 
  $self->listeners->{$id}->set_port($port) if $port;

  ## Tell our controller session
  ##  Event: listener_added $addr, $port, $wheel_id
  $kernel->post( $self->controller, 
    'ircsock_listener_created',
    $addr, $port, $id
  );
}

sub remove_listener {
  my $self = shift;

  $poe_kernel->post( $self->session_id,
    'remove_listener', 
    @_ 
  );

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

  $poe_kernel->post( $self->session_id,
    'create_connector',
    @_
  );

  1
}

sub _create_connector {
  ## Connector; try to spawn socket <-> remote peer
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
  
  $self->connectors->{$id} = IRC::Server::Pluggable::IRCSock::Connector->new(
    wheel => $wheel,
    addr  => $remote_addr,
    port  => $remote_port,
    (defined $args{bindaddr} ? (bindaddr => $args{bindaddr}) : () ),
  );
  
  ## FIXME ssl .. ?
}


sub _ircsock_up {
  ## Created connector socket.
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($sock, $peeraddr, $peerport, $c_id) = @_[ARG0 .. ARG3];

  $peeraddr = inet_ntoa($peeraddr);

  my $ct = delete $self->connectors->{$c_id};

  if ( $ct->ssl ) {
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
    )
  );

  my $w_id = $wheel->ID;

  my $sockaddr = inet_ntoa( 
    ( unpack_sockaddr_in(getsockname $sock) )[1] 
  );
  my $sockport = ( unpack_sockaddr_in(getsockname $sock) )[0];

  ## FIXME objs
  my $ref = {
    wheel => $wheel,
    peeraddr => $peeraddr,
    peerport => $peerport,
    sockaddr => $sockaddr,
    sockport => $sockport,
    ## FIXME idle / compression ?
  };
  
  $self->wheels->{$w_id} = $ref;
  
  $kernel->post( $self->controller, 
    'ircsock_peer_connected',
    $w_id, $peeraddr, $peerport, $sockaddr, $sockport
  );
}

sub _ircsock_failed {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($op, $errno, $errstr, $c_id) = @_[ARG0 .. ARG3];

  my $ct = delete $self->connectors->{$c_id};
  $ct->clear_wheel;

  $kernel->post( $self->controller, 
    'ircsock_socketerr',
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
  $kernel->post( $self->controller, 
    'ircsock_ev_'.$input->{command},
    $input 
  );
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

1;
__END__

## FIXME listener connect ip blacklist?
