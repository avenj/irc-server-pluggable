package IRC::Server::Pluggable::Backend;
our $VERSION = '0.000_01';

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable qw/
  Backend::Connect
  Backend::Connector
  Backend::Listener

  IRC::Event

  Types
  Utils
/;

use Net::IP::Minimal qw/
  ip_is_ipv6
/;

use POE qw/
  Session

  Wheel::ReadWrite
  Wheel::SocketFactory

  Component::SSLify

  Filter::Stackable
  Filter::IRCD
  Filter::Line

  Filter::Zlib::Stream
/;

use Socket qw/
  :addrinfo
  AF_INET
  AF_INET6
/;

use Try::Tiny;

use namespace::clean -except => 'meta';

has 'session_id' => (
  ## Session ID for own session.
  init_arg => undef,
  lazy => 1,

  is  => 'ro',

  writer    => 'set_session_id',
  predicate => 'has_session_id',

  default => sub { undef },
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

  isa => InstanceOf['POE::Filter'],
  is  => 'rwp',

  default => sub {
    POE::Filter::IRCD->new( colonify => 1 )
  },
);

has 'filter_line' => (
  lazy => 1,

  isa => InstanceOf['POE::Filter'],
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

  isa => InstanceOf['POE::Filter'],
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

## IRC::Server::Pluggable::Backend::Connect objs
## These are our connected wheels.
has 'wheels' => (
  is  => 'rwp',
  isa => HashRef,
  default => sub { {} },
  clearer => 1,
);


has '__backend_class_prefix' => (
  is      => 'rw',
  default => sub { 'IRC::Server::Pluggable::Backend::' },
);

has '__backend_listener_class' => (
  lazy    => 1,
  is      => 'rw',
  default => sub { $_[0]->__backend_class_prefix . 'Listener' },
);

has '__backend_connector_class' => (
  lazy    => 1,
  is      => 'rw',
  default => sub { $_[0]->__backend_class_prefix . 'Connector' },
);

has '__backend_connect_class' => (
  lazy    => 1,
  is      => 'rw',
  default => sub { $_[0]->__backend_class_prefix . 'Connect' },
);

has '__backend_event_class' => (
  lazy    => 1,
  is      => 'rw',
  default => sub { 'IRC::Server::Pluggable::IRC::Event' },
);

sub spawn {
  ## Create our object and session.
  ## Returns $self
  ## Sets session_id()
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

        'send' => '_send',

        'create_listener' => '_create_listener',
        'remove_listener' => '_remove_listener',

        '_accept_conn' => '_accept_conn',
        '_accept_fail' => '_accept_fail',
        '_idle_alarm'  => '_idle_alarm',

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
  ##  FIXME document that we need a pubkey + cert for server-side ssl
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

  $self
}


sub _start {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  $self->set_session_id( $_[SESSION]->ID );
  $kernel->refcount_increment( $self->session_id, "IRCD Running" );
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

  $kernel->refcount_decrement( $self->session_id, "IRCD Running" );
  $kernel->refcount_decrement( $self->controller, "IRCD Running" );

  ## _disconnected should also clear our alarms.
  $self->_disconnected($_, "Server shutdown")
    for keys %{ $self->wheels };

  $self->clear_listeners;
  $self->clear_connectors;
  $self->clear_wheels;
}

sub _register_controller {
  ## 'register' event sets a controller session.
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $self->set_controller( $_[SENDER]->ID );

  $kernel->refcount_increment( $self->controller, "IRCD Running" );

  $kernel->post( $self->controller, 'ircsock_registered', $self );
}

sub _accept_conn {
  ## Accepted connection to a listener.
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($sock, $p_addr, $p_port, $listener_id) = @_[ARG0 .. ARG3];

  ## Our sock addr/port.
  my $sock_packed = getsockname($sock);
  my ($protocol, $sockaddr, $sockport) = get_unpacked_addr($sock_packed);

  ## Our peer's addr.
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
    InputEvent   => '_ircsock_input',
    ErrorEvent   => '_ircsock_error',
    FlushedEvent => '_ircsock_flushed',
  );

  unless ($wheel) {
    carp "Wheel creation failure in _accept_conn";
    return
  }

  my $w_id = $wheel->ID;

  my $this_conn = $self->__backend_connect_class->new(
    protocol => $protocol,
    wheel    => $wheel,

    peeraddr => $p_addr,
    peerport => $p_port,

    sockaddr => $sockaddr,
    sockport => $sockport,

    seen => time,
    idle => $listener->idle,
  );

  $self->wheels->{$w_id} = $this_conn;

  $this_conn->alarm_id(
    $kernel->delay_set(
      '_idle_alarm',
      $this_conn->idle,
      $w_id
    )
  );

  $kernel->post( $self->controller,
    'ircsock_listener_open',
    $this_conn
  );
}

sub _idle_alarm {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $w_id = $_[ARG0];

  my $this_conn = $self->wheels->{$w_id} || return;

  $kernel->post( $self->controller,
    'ircsock_connection_idle',
    $this_conn
  );

  $this_conn->alarm_id(
    $kernel->delay_set(
      '_idle_alarm',
      $this_conn->idle,
      $w_id
    )
  );
}

sub _accept_fail {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($op, $errnum, $errstr, $listener_id) = @_[ARG0 .. ARG3];

  my $listener = delete $self->listeners->{$listener_id};

  if ($listener) {
    $listener->clear_wheel;

    $kernel->post( $self->controller,
      'ircsock_listener_failure',
      $listener, $op, $errnum, $errstr
    );
  }
}


sub create_listener {
  my $self = shift;

  $poe_kernel->post( $self->session_id,
    'create_listener',
    @_
  );

  $self
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

  my $idle_time = delete $args{idle}     || 180;

  my $bindaddr  = delete $args{bindaddr} || '0.0.0.0';
  my $bindport  = delete $args{port}     || 0;

  my $protocol = 4;
  $protocol = 6
    if delete $args{ipv6} or ip_is_ipv6($bindaddr);

  my $ssl = delete $args{ssl} || 0;

  my $wheel = POE::Wheel::SocketFactory->new(
    SocketDomain => $protocol == 6 ? AF_INET6 : AF_INET,
    BindAddress  => $bindaddr,
    BindPort     => $bindport,
    SuccessEvent => '_accept_conn',
    FailureEvent => '_accept_fail',
    Reuse        => 1,
  );

  my $id = $wheel->ID;

  my $listener = $self->__backend_listener_class->new(
    protocol => $protocol,
    wheel => $wheel,
    addr  => $bindaddr,
    port  => $bindport,
    idle  => $idle_time,
    ssl   => $ssl,
  );

  $self->listeners->{$id} = $listener;

  ## Real bound port/addr
  my ($proto, $addr, $port) = get_unpacked_addr( $wheel->getsockname );
  $listener->set_port($port) if $port;

  ## Tell our controller session
  $kernel->post( $self->controller,
    'ircsock_listener_created',
    $listener
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

  $self
}

sub _remove_listener {
  ## Delete listeners by ID or by port.
  ## FIXME delete by addr+port combo ?
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

  $self
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

  my $protocol = 4;
  $protocol = 6
    if delete $args{ipv6} or ip_is_ipv6($remote_addr);

  my $wheel = POE::Wheel::SocketFactory->new(
    SocketDomain   => $protocol == 6 ? AF_INET6 : AF_INET,
    SocketProtocol => 'tcp',

    RemoteAddress  => $remote_addr,
    RemotePort     => $remote_port,

    SuccessEvent   => '_connector_up',
    FailureEvent   => '_connector_failed',

    (defined $args{bindaddr} ?
      (BindAddress => delete $args{bindaddr}) : () ),
  );

  my $id = $wheel->ID;

  $self->connectors->{$id} = $self->__backend_connector_class->new(
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

  unless ($wheel) {
    carp "Wheel creation failure in _accept_conn";
    return
  }

  my $w_id = $wheel->ID;

  my $sock_packed = getsockname($sock);
  my ($protocol, $sockaddr, $sockport)
    = get_unpacked_addr($sock_packed);

  my $this_conn = $self->__backend_connect_class->new(
    protocol => $protocol,
    wheel    => $wheel,
    peeraddr => $peeraddr,
    peerport => $peerport,
    sockaddr => $sockaddr,
    sockport => $sockport,
    seen => time,
    ## FIXME some way to set an idle timeout for these?
    ##  otherwise defaults to 180 ...
  );

  ## FIXME?
  ##  Doesn't currently spawn an idle alarm for this conn
  ##  (Presumably a remote server)
  ##  No big deal for connect-time since the Connector will time-out
  ##  However, no idle event is sent so higher levels won't ping out . . .

  $self->wheels->{$w_id} = $this_conn;

  $kernel->post( $self->controller,
    'ircsock_connector_open',
    $this_conn
  );
}

sub _connector_failed {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($op, $errno, $errstr, $c_id) = @_[ARG0 .. ARG3];

  my $ct = delete $self->connectors->{$c_id};
  $ct->clear_wheel;

  $kernel->post( $self->controller,
    'ircsock_connector_failure',
    $ct, $op, $errno, $errstr
  );
}

## _ircsock_* handlers talk to endpoints via listeners/connectors
sub _ircsock_input {
  ## Input handler.
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($input, $w_id)  = @_[ARG0, ARG1];

  ## Retrieve Backend::Connect
  my $this_conn = $self->wheels->{$w_id};

  ## Disconnecting? Don't care.
  return if $this_conn->is_disconnecting;

  ## Adjust last seen and idle alarm
  $this_conn->seen( time );
  $kernel->delay_adjust( $this_conn->alarm_id, $this_conn->idle )
    if $this_conn->has_alarm_id;

  ## FIXME configurable raw events?
  ## FIXME anti-flood code or should that be higher up ... ?

  ## Create obj from HASH from POE::Filter::IRCD
  my $obj = $self->__backend_event_class->new(
    %$input
  );

  ## Send ircsock_input to controller/dispatcher
  $kernel->post( $self->controller,
    'ircsock_input',
    $this_conn,
    $obj
  );
}

sub _ircsock_error {
  ## Lost someone.
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($errstr, $w_id) = @_[ARG2, ARG3];

  my $this_conn;
  return unless $this_conn = $self->wheels->{$w_id};

  $self->_disconnected(
    $w_id,
    $errstr || $this_conn->is_disconnecting
  );
}

sub _ircsock_flushed {
  ## Socket's been flushed; we may have something to do.
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
    $self->set_compressed_link_now($w_id);
    return
  }

}

sub _send {
  ## POE bridge to send()
  $_[OBJECT]->send(@_[ARG0 .. $#_ ]);
}

## Methods.

sub send {
  ## ->send(HASH, ID [, ID .. ])
  my ($self, $out, @ids) = @_;

  if (is_Object($out) &&
    $out->isa( $self->__backend_event_class ) ) {

    $out = {
      prefix  => $out->prefix,
      params  => $out->params,
      command => $out->command,
    };
  }

  unless (@ids && ref $out eq 'HASH') {
    carp "send() takes a HASH and a list of connection IDs";
    return
  }

  for my $id (grep { $self->wheels->{$_} } @ids) {
    $self->wheels->{$id}->wheel->put( $out );
  }

  $self
}

sub disconnect {
  ## Mark a wheel for disconnection.
  my ($self, $w_id, $str) = @_;

  confess "disconnect() needs a wheel ID"
    unless defined $w_id;

  return unless $self->wheels->{$w_id};

  $self->wheels->{$w_id}->is_disconnecting(
    $str || "Client disconnect"
  );

  $self
}

sub _disconnected {
  ## Wheel needs cleanup.
  my ($self, $w_id, $str) = @_;
  return unless $w_id and $self->wheels->{$w_id};

  my $this_conn = delete $self->wheels->{$w_id};

  ## Idle timer cleanup
  $poe_kernel->alarm_remove( $this_conn->alarm_id )
    if $this_conn->has_alarm_id;

  if ($^O =~ /(cygwin|MSWin32)/) {
    $this_conn->wheel->shutdown_input;
    $this_conn->wheel->shutdown_output;
  }

  ## Higher layers may still have a $conn object bouncing about.
  ## They should check ->has_wheel to determine if the Connect obj
  ## has been disconnected (no longer has a wheel).
  $this_conn->clear_wheel;

  $poe_kernel->post( $self->controller,
    'ircsock_disconnect',
    $this_conn,
    $str
  );

  1
}

sub set_compressed_link {
  my ($self, $w_id) = @_;

  confess "set_compressed_link() needs a wheel ID"
    unless defined $w_id;

  return unless $self->wheels->{$w_id};

  $self->wheels->{$w_id}->is_pending_compress(1);

  $self
}

sub set_compressed_link_now {
  my ($self, $w_id) = @_;

  confess "set_compressed_link() needs a wheel ID"
    unless defined $w_id;

  my $this_conn;
  return unless $this_conn = $self->wheels->{$w_id};

  $this_conn->wheel->get_input_filter->unshift(
    POE::Filter::Zlib::Stream->new,
  );

  $this_conn->is_pending_compress(0);
  $this_conn->set_compressed(1);

  $poe_kernel->post( $self->controller,
    'ircsock_compressed',
    $this_conn
  );

  $self
}

sub unset_compressed_link {
  my ($self, $w_id) = @_;

  confess "unset_compressed_link() needs a wheel ID"
    unless defined $w_id;

  my $this_conn;
  return unless $this_conn = $self->wheels->{$w_id};

  return unless $this_conn->compressed;

  $this_conn->wheel->get_input_filter->shift;

  $this_conn->set_compressed(0);

  $self
}

## FIXME listener connect ip blacklist?

no warnings 'void';
q{
 <CaptObviousman> pretend for a moment that I'm stuck with mysql
 <rnowak> ok, fetching my laughing hat and monocle
};


=pod

=head1 NAME

IRC::Server::Pluggable::Backend - IRC socket handler backend

=head1 SYNOPSIS

  ## Spawn a Backend and register as the controlling session.
  my $backend = IRC::Server::Pluggable::Backend->spawn(
    ## See POE::Component::SSLify (SSLify_Options):
    ssl_opts => [ ARRAY ],
  );

  $poe_kernel->post( $backend->session_id, 'register' );

  $backend->create_listener(
    bindaddr => ADDR,
    port     => PORT,
    ## Optional:
    ipv6     => BOOLEAN,
    ssl      => BOOLEAN,
  );

  $backend->create_connector(
    remoteaddr => ADDR,
    remoteport => PORT,
    ## Optional:
    bindaddr => ADDR,
    ipv6     => BOOLEAN,
    ssl      => BOOLEAN,
  );

  ## Handle and dispatch incoming IRC events.
  sub ircsock_input {
    my ($kernel, $self) = @_[KERNEL, OBJECT];

    ## IRC::Server::Pluggable::Backend::Connect obj:
    my $this_conn = $_[ARG0];

    ## IRC::Server::Pluggable::IRC::Event obj:
    my $input_obj = $_[ARG1];

    my $cmd = $input_obj->command;

    ## ... dispatch, etc ...
  }

=head1 DESCRIPTION

A L<POE> IRC backend socket handler based loosely on
L<POE::Component::Server::IRC>.


=head2 Methods

=head3 spawn

  my $backend = IRC::Server::Pluggable::Backend->spawn(
    ## Optional, needed for SSL-ified server-side sockets
    ssl_opts => [
      'server.key',
      'server.cert',
    ],
  );

=head3 controller

Retrieve session ID for the backend's registered controller.

=head3 create_connector

  $backend->create_connector(
    remoteaddr => $addr,
    remoteport => $addr,
    ## Optional:
    bindaddr => $local_addr,
    ipv6 => 1,
    ssl  => 1,
  );

Attempts to create a L<IRC::Server::Pluggable::Backend::Connector> that 
holds a L<POE::Wheel::SocketFactory> connector wheel; connectors will 
attempt to establish an outgoing connection immediately.

=head3 create_listener

  $backend->create_listener(
    bindaddr => $addr,
    port     => $port,
    ## Optional:
    ipv6     => 1,
    ssl      => 1,
    idle     => $seconds,
  );

Attempts to create a L<IRC::Server::Pluggable::Backend::Listener> 
that holds a L<POE::Wheel::SocketFactory> listener wheel.

=head3 remove_listener

FIXME

=head3 disconnect

  $backend->disconnect($wheel_id, $disconnect_string);

Given a connection's wheel ID, mark the specified wheel for 
disconnection.

=head3 send

  $backend->send(
    {
      prefix  =>
      params  =>
      command =>
    },

    $conn_id,
  );

Feeds L<POE::Filter::IRCD> and sends the resultant raw IRC line to the 
specified connection wheel ID.

=head3 session_id

Returns the backend's session ID.

=head3 set_compressed_link

  $backend->set_compressed_link( $conn_id );

Mark a specified connection wheel ID as pending compression; 
L<POE::Filter::Zlib::Stream> will be added to the filter stack when the 
next flush event arrives.

=head3 set_compressed_link_now

  $backend->set_compressed_link_now( $conn_id );

Add a L<POE::Filter::Zlib::Stream> to the connection's filter stack 
immediately, rather than upon next flush event.

=head3 unset_compressed_link

  $backend->unset_compressed_link( $conn_id );

Remove L<POE::Filter::Zlib::Stream> from the connection's filter stack.


=head2 Received events

=head3 register

  $poe_kernel->post( $backend->session_id,
    'register'
  );

Register the sender session as the backend's controller session. The last 
session to send 'register' is the session that receives notification 
events from the backend component.

=head3 create_connector

Event interface to I<create_connector> -- see L</Methods>

=head3 create_listener

Event interface to I<create_listener> -- see L</Methods>

=head3 remove_listener

Event interface to I<remove_listener> -- see L</Methods>

=head3 send

Event interface to I</send> -- see L</Methods>

=head3 shutdown

Disconnect all wheels and clean up.


=head2 Dispatched events

These events are dispatched to the controller session; see L</register>.

=head3 ircsock_compressed

Dispatched when a connection wheel has had a compression filter added.

C<$_[ARG0]> is the connection's 
L<IRC::Server::Pluggable::Backend::Connect>

=head3 ircsock_connection_idle

Dispatched when a connection wheel has had no input for longer than 
specified idle time (see L</create_listener> regarding idle times).

C<$_[ARG0]> is the connection's 
L<IRC::Server::Pluggable::Backend::Connect>

=head3 ircsock_connector_failure

Dispatched when a Connector has failed due to some sort of socket error.

C<$_[ARG0]> is the connection's 
L<IRC::Server::Pluggable::Backend::Connector> with wheel() cleared.

C<@_[ARG1 .. ARG3]> contain the socket error details reported by 
L<POE::Wheel::SocketFactory>; operation, errno, and errstr, respectively.

=head3 ircsock_connector_open

Dispatched when a Connector has established a connection to a peer.

C<$_[ARG0]> is the L<IRC::Server::Pluggable::Backend::Connect> for the 
connection.

=head3 ircsock_disconnect

Dispatched when a connection wheel has been cleared.

C<$_[ARG0]> is the connection's L<IRC::Server::Pluggable::Backend::Connect> 
with wheel() cleared.

=head3 ircsock_input

Dispatched when there is some IRC input from a connection wheel.

C<$_[ARG0]> is the connection's 
L<IRC::Server::Pluggable::Backend::Connect>.

C<$_[ARG1]> is a L<IRC::Server::Pluggable::IRC::Event>.

=head3 ircsock_listener_created

Dispatched when a L<IRC::Server::Pluggable::Backend::Listener> has been 
created.

C<$_[ARG0]> is the L<IRC::Server::Pluggable::Backend::Listener> instance; 
the instance's port() is altered based on getsockname() details after 
socket creation and before dispatching this event.

=head3 ircsock_listener_failure

Dispatched when a Listener has failed due to some sort of socket error.

C<$_[ARG0]> is the L<IRC::Server::Pluggable::Backend::Listener> object.

C<@_[ARG1 .. ARG3]> contain the socket error details reported by 
L<POE::Wheel::SocketFactory>; operation, errno, and errstr, respectively.

=head3 ircsock_listener_open

Dispatched when a listener accepts a connection.

C<$_[ARG0]> is the connection's L<IRC::Server::Pluggable::Backend::Connect>

=head3 ircsock_listener_removed

Dispatched when a Listener has been removed.

C<$_[ARG0]> is the L<IRC::Server::Pluggable::Backend::Listener> object.

=head3 ircsock_registered

Dispatched when a L</register> event has been successfully received, as a 
means of acknowledging the controlling session.

C<$_[ARG0]> is the Backend's C<$self> object.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

Modelled on L<POE::Component::Server::IRC::Backend>

=cut

