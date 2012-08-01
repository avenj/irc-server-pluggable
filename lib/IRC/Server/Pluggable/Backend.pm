package IRC::Server::Pluggable::Backend;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable::Backend::Connector;
use IRC::Server::Pluggable::Backend::Listener;
use IRC::Server::Pluggable::Backend::Wheel;

use IRC::Server::Pluggable::Types;

use Net::IP::Minimal qw/
  ip_is_ipv6
/;

use POE qw/
  Session

  Wheel::SocketFactory

  Component::SSLify
  
  Filter::Stackable
  Filter::IRCD
  Filter::Line
/;

use Socket qw/
  :addrinfo

  AF_INET
  inet_ntoa
  unpack_sockaddr_in

  AF_INET6
  inet_ntop
  unpack_sockaddr_in6
/;

use Try::Tiny;


has 'session_id' => (
  ## Session ID for own session.
  lazy => 1,
  
  isa  => Value,
  is => 'ro',
  
  writer    => 'set_session_id',
  predicate => 'has_session_id',
);

has 'controller' => (
  ## Session ID for controller session
  ## Set by 'register' event
  lazy => 1,

  isa  => Value,
  is   => 'ro',

  writer    => 'set_controller',
  predicate => 'has_controller',
);

has 'filter_irc' => (
  lazy => 1,
  
  isa => Filter,
  is  => 'rwp',

  default => sub { 
    POE::Filter::IRCD->new( colonify => 1 ) 
  },
);

has 'filter_line' => (
  lazy => 1,

  isa => Filter,
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

  isa => Filter,
  is  => 'rwp',

  default => sub {
    my ($self) = @_;

    POE::Filter::Stackable->new(
      Filters => [ $self->filter_line, $self->filter_irc ],
    );
  },
);

## IRC::Server::Pluggable::Backend::Listener objs
## These are listeners for a particular port.
has 'listeners' => (
  is  => 'rwp',
  isa => HashRef,
  default => sub { {} },
  clearer => 1,
);

## IRC::Server::Pluggable::Backend::Connector objs
## These are outgoing (peer) connectors.
has 'connectors' => (
  is  => 'rwp',
  isa => HashRef,
  default => sub { {} },
  clearer => 1,
);

## IRC::Server::Pluggable::Backend::Wheel objs
## These are our connected wheels.
has 'wheels' => (
  is  => 'rwp',
  isa => HashRef,  
  default => sub { {} },
  clearer => 1,
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
        
        'register' => '_register_controller',
        'shutdown' => '_shutdown',
                
        'create_listener' => '_create_listener',
        'remove_listener' => '_remove_listener',

        '_accept_conn' => '_accept_conn',
        '_accept_fail' => '_accept_fail',
        
        'create_connector'  => '_create_connector',
        '_connector_up'     => '_connector_up',
        '_connector_failed' => '_connector_failed',
        
        '_ircsock_input'    => '_ircsock_input',
        '_ircsock_error'    => '_ircsock_error',
        '_ircsock_flushed'  => '_ircsock_flushed',
      },
    ],
  )->ID;
  
  confess "Unable to spawn POE::Session and retrieve ID()"
    unless $sess_id;

  ## ssl_opts => [ ]
  if ($args{ssl_opts}) {
    confess "ssl_opts should be an ARRAY"
      unless ref $args{ssl_opts} eq 'ARRAY';
    
    my $ssl_err;
    try {
      POE::Component::SSLify::SSLify_Options(
        @{ $args{ssl_opts} }
      );

      1
    } catch {
      $ssl_err = $_;

      undef
    } or confess "SSLify failure: $ssl_err";
  }

  ## FIXME add listeners / connectors here if they're configured?

  $self->set_session_id( $sess_id );
  
  $self
}


sub _start {

}

sub _stop {

}

sub shutdown {
  my $self = shift;

  $poe_kernel->post( $self->session_id,
    'shutdown', 
    @_
  );

  1
}

sub _shutdown {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $kernel->refcount_decrement( $self->controller, "IRCD Running" );

  $self->_disconnected($_, "Server shutdown")
    for keys %{ $self->wheels };

  $self->clear_listeners;
  $self->clear_connectors;
  $self->clear_wheels;
}

sub _register_controller {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $self->set_controller( $_[SENDER]->ID );
  
  $kernel->refcount_increment( $self->controller, "IRCD Running" );
}

sub _accept_conn {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($sock, $p_addr, $p_port, $listener_id) = @_[ARG0 .. ARG3];

  ## Accepted connection to a listener.

  my $inet_proto;  
  my $sock_packed = getsockname($sock);
  my $sock_family = socketaddr_family($sock_packed);

  ## TODO getnameinfo instead?
  my($sockaddr, $sockport);
  if ($sock_family == AF_INET6) {
    $inet_proto = 6;
    ($sockport, $sockaddr) = unpack_sockaddr_in6($sock_packed);
    $sockaddr = inet_ntop($sockaddr);
  } elsif ($sock_family == AF_INET) {
    $inet_proto = 4;
    ($sockport, $sockaddr) = unpack_sockaddr_in($sock_packed);
    $sockaddr = inet_ntoa($sockaddr);
  } else {
    croak "Unknown socket family type in _accept_conn"
  }

  my $n_err;
  ($n_err, $p_addr) = getnameinfo( 
   $p_addr,
   NI_NUMERICHOST | NIx_NOSERV
 );
  
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

  my $obj = IRC::Server::Pluggable::Backend::Wheel->new(
    protocol => $inet_proto,
    wheel    => $wheel,
    peeraddr => $p_addr,
    peerport => $p_port,
    sockaddr => $sockaddr,
    sockport => $sockport,
  );

  $self->wheels->{$w_id} = $obj;

  $kernel->post( $self->controller,
    'ircsock_client_connected',
    $obj
  );
}

sub _accept_fail {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($op, $errnum, $errstr, $listener_id) = @_[ARG0 .. ARG3];

  ## TODO Hmm .. is clearing the listener the right thing to do?
  ##   PoCo::Server::IRC::Backend does it this way ...
  
  my $listener = delete $self->listeners->{$listener_id};
  if ($listener) {
    $listener->clear_wheel;
    
    $kernel->post( $self->controller,
      'ircsock_listener_failure',
      $listener
    );
  }
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
  ##  bindaddr =>
  ##  port =>
  ## [optional]
  ##  ipv6 =>
  ##  ssl  =>
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my %args = @_[ARG0 .. $#_];

  $args{lc $_} = delete $args{$_} for keys %args;
  
  my $bindaddr  = delete $args{bindaddr} || '0.0.0.0';
  my $bindport  = delete $args{port}     || 0;

  my $inet_proto = 4;
  $inet_proto = 6
    if delete $args{ipv6} or ip_is_ipv6($bindaddr);

  my $idle_time = delete $args{idle}     || 180;

  my $ssl = delete $args{ssl} || 0;

  my $wheel = POE::Wheel::SocketFactory->new(
    SocketDomain => $inet_proto == 6 ? AF_INET6 : AF_INET,
    BindAddress  => $bindaddr,
    BindPort     => $bindport,
    SuccessEvent => '_accept_conn',
    FailureEvent => '_accept_fail',
    Reuse        => 1,
  );

  my $id = $wheel->ID;

  $self->listeners->{$id} = IRC::Server::Pluggable::Backend::Listener->new(
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

  my %args = @_;
  $args{lc $_} = delete $args{$_} for keys %args;

  confess "remove_listener requires either port => or listener => params"
    unless defined $args{port} or defined $args{listener};

  $poe_kernel->post( $self->session_id,
    'remove_listener', 
    @_ 
  );

  1
}

sub _remove_listener {
  ## Delete listeners by ID or by port.
  ## TODO delete by addr+port combo ?
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my %args = @_[ARG0 .. $#_];

  $args{lc $_} = delete $args{$_} for keys %args;

  if (defined $args{port}) {
    LISTENER: for my $id (keys %{ $self->listeners }) {
      my $listener = $self->listeners->{$id};
      if ($args{port} == $listener->port) {
        delete $self->listeners->{$id};
        
        $listener->clear_wheel;
        
        $kernel->post( $self->controller,
          'ircsock_listener_removed',
          $listener
        );
      }
    } ## LISTENER

    return
  }

  if (defined $args{listener}) {

    if ($self->listeners->{ $args{listener} }) {
      my $listener = delete $self->listeners->{ $args{listener} };

      $listener->clear_wheel;
      
      $kernel->post( $self->controller,
        'ircsock_listener_removed',
        $listener
      );
    }

  }
  
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
  ##  remoteaddr =>
  ##  remoteport =>
  ## [optional] 
  ##  bindaddr =>
  ##  ipv6 =>
  ##  ssl  =>
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my %args = @_[ARG0 .. $#_];

  $args{lc $_} = delete $args{$_} for keys %args;

  my $remote_addr = delete $args{remoteaddr};
  my $remote_port = delete $args{remoteport};

  confess "_create_connector expects a RemoteAddr and RemotePort"
    unless defined $remote_addr and defined $remote_port;

  my $inet_proto = 4;
  $inet_proto = 6
    if delete $args{ipv6} or ip_is_ipv6($remote_addr);

  my $wheel = POE::Wheel::SocketFactory->new(
    SocketDomain   => $inet_proto == 6 ? AF_INET6 : AF_INET,
    SocketProtocol => 'tcp',

    RemoteAddress  => $remote_addr,
    RemotePort     => $remote_port,

    SuccessEvent   => '_connector_up',
    FailureEvent   => '_connector_failed',

    (defined $args{bindaddr} ? 
      (BindAddress => delete $args{bindaddr}) : () ),
  );

  my $id = $wheel->ID;
  
  $self->connectors->{$id} = IRC::Server::Pluggable::Backend::Connector->new(
    wheel => $wheel,
    addr  => $remote_addr,
    port  => $remote_port,

    (defined $args{ssl}      ? 
      (ssl      => delete $args{ssl}) : () ),

    (defined $args{bindaddr} ? 
      (bindaddr => delete $args{bindaddr}) : () ),

    ## Attach any extra args to Connector->args()
    (keys %args ?
      (args => \%args) : () ),
  );
}


sub _connector_up {
  ## Created connector socket.
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($sock, $peeraddr, $peerport, $c_id) = @_[ARG0 .. ARG3];

  my $n_err;
  ($n_err, $peeraddr) = getnameinfo( $peeraddr,
    NI_NUMERICHOST | NIx_NOSERV
  );

  ## No need to try to connect out any more; remove from connectors pool
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

  my $inet_proto;
  my $sock_packed = getsockname($sock);
  my $sock_family = socketaddr_family($sock_packed);

  my($sockaddr, $sockport);
  if ($sock_family == AF_INET6) {
    $inet_proto = 6;
    ($sockport, $sockaddr) = unpack_sockaddr_in6($sock_packed);
    $sockaddr = inet_ntop($sockaddr);
  } elsif ($sock_family == AF_INET) {
    $inet_proto = 4;
    ($sockport, $sockaddr) = unpack_sockaddr_in($sock_packed);
    $sockaddr = inet_ntoa($sockaddr);
  } else {
    croak "Unknown socket family type in _connector_up"
  }

  my $obj = IRC::Server::Pluggable::Backend::Wheel->new(
    protocol => $inet_proto,
    wheel    => $wheel,
    peeraddr => $peeraddr,
    peerport => $peerport,
    sockaddr => $sockaddr,
    sockport => $sockport,
    ## FIXME idle / compression ?
  );
  
  $self->wheels->{$w_id} = $obj;
  
  $kernel->post( $self->controller, 
    'ircsock_peer_connected',
    $obj
  );
}

sub _connector_failed {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($op, $errno, $errstr, $c_id) = @_[ARG0 .. ARG3];

  my $ct = delete $self->connectors->{$c_id};
  $ct->clear_wheel;

  $kernel->post( $self->controller, 
    'ircsock_socketerr',
    $ct, $op, $errno, $errstr
  );
}

## _ircsock_* handlers talk to endpoints via listeners/connectors
sub _ircsock_input {
  ## Input handler.
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($input, $w_id)  = @_[ARG0, ARG1];

  ## Retrieve Backend::Wheel
  my $this_conn = $self->wheels->{$w_id};

  ## TODO raw events?
  ## TODO idle adjust?
  ## TODO anti-flood code or should that be higher up ... ?

  ## Create obj from HASH from POE::Filter::IRCD
  my $obj = IRC::Server::Pluggable::Backend::Event->new(
    %$input
  );

  ## Send ircsock_incoming to controller/dispatcher
  $kernel->post( $self->controller, 
    'ircsock_incoming',
    $obj
  );
}

sub _ircsock_error {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($errstr, $w_id) = @_[ARG2, ARG3];

  my $this_conn;
  return unless $this_conn = $self->wheels->{$w_id};

  $self->_disconnected(
    $w_id,
    $errstr || $self->wheels->{$w_id}->is_disconnecting
  );
}

sub _ircsock_flushed {
  my ($kernel, $self, $w_id) = @_[KERNEL, OBJECT, ARG0];

  my $this_conn;
  return unless $this_conn = $self->wheels->{$w_id};

  if ($this_conn->is_disconnecting) {
    $self->_disconnected(
      $w_id,
      $this_conn->is_disconnecting
    );
    return
  }
  
  if ($this_conn->is_pending_compress) {
    $this_conn->is_pending_compress(0);

    $this_conn->wheel->get_input_filter->unshift(
      POE::Filter::Zlib::Stream->new,
    );

    $kernel->post( $self->controller,
      'ircsock_compressed',
      $this_conn
    );
    
    return
  }
  
}

## FIXME idle alarm ?

## Methods.
sub disconnect {
  ## Mark a wheel for disconnection.
  my ($self, $w_id, $str) = @_;
  
  confess "disconnect() needs a wheel ID"
    unless defined $w_id;

  return unless $self->wheels->{$w_id};
  
  $self->wheels->{$w_id}->is_disconnecting(
    $str || "Client disconnect"
  );

  1
}

sub _disconnected {
  ## Wheel needs cleanup.
  my ($self, $w_id, $str) = @_;
  return unless $w_id and $self->wheels->{$w_id};
  
  my $this_conn = delete $self->wheels->{$w_id};
  
  ## FIXME idle timer cleanup ?
  
  $poe_kernel->post( $self->controller,
    'ircsock_disconnect',
    ## FIXME
  );
  
  if ($^O =~ /(cygwin|MSWin32)/) {
    $this_conn->wheel->shutdown_input;
    $this_conn->wheel->shutdown_output;
  }

  1
}

## FIXME method to set up a compressed link ?


1;
__END__

## FIXME listener connect ip blacklist?
