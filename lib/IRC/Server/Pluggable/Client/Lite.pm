package IRC::Server::Pluggable::Client::Lite;

use 5.12.1;
use Moo;
use POE;


use MooX::Struct -rw,
  State => [ qw/
    @channels
    nick_name
    server_name
  / ],

  Channel => [ qw/
    @nicknames
    topic
  / ],
;

use IRC::Server::Pluggable qw/
  Backend
  IRC::Event
  IRC::Filter
  Utils::Parse::CTCP
  Types
/;

my $filter = prefixed_new( 'IRC::Filter' => 
  colonify => 0,
);

with 'MooX::Role::POE::Emitter';
use MooX::Role::Pluggable::Constants;

has backend => (
  lazy    => 1,
  is      => 'ro',
  isa     => InstanceOf['IRC::Server::Pluggable::Backend'],
  builder => '_build_backend',
);

has conn => (
  lazy      => 1,
  weak_ref  => 1,
  is        => 'ro',
  isa       => Defined,
  writer    => '_set_conn',
  predicate => '_has_conn',
  clearer   => '_clear_conn',
);

has state => (
  lazy    => 1,
  is      => 'ro',
  isa     => Object,
  default => sub { 
    State[
      channels    => [],
      nick_name   => '',
      server_name => '',
    ]
  },
);

sub _build_backend {
  my ($self) = @_;
  prefixed_new( 'Backend' =>
    filter_irc => prefixed_new( 'IRC::Filter', colonify => 1 );
  );
  ## FIXME create a Backend with a non-colonifying filter?
  ##  events can be spawned with a filter => specified also ..
  ##  possible we should have a filter attrib passed to ev()
  ##  . . . not sure if we need to
}

sub BUILD {
  my ($self) = @_;

  $self->set_object_states(
    [
      $self => [ qw/
        ircsock_input
        ircsock_connector_open
        ircsock_connector_failure
        ircsock_disconnect
      / ],
      $self => {
        connect_to  => '_connect_to',
        disconnect  => '_disconnect',
        send        => '_send',
        privmsg     => '_privmsg',
        ctcp        => '_ctcp',
        notice      => '_notice',
        mode        => '_mode',
        join        => '_join',
        part        => '_part',
      },
      (
        $self->has_object_states ? @{ $self->object_states } : ()
      ),
    ],
  );

  $self->set_event_prefix('irc_client_')
    unless $self->has_event_prefix;
  
  $self->_start_emitter;
}

sub _emitter_started {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  $kernel->post( $self->backend->session_id, 'register' );
}

sub stop {
  my ($self) = @_;
  $poe_kernel->post( $self->backend->session_id, 'shutdown' );
  $self->_shutdown_emitter;
}

### ircsock_*

sub ircsock_connector_open {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $conn = $_[ARG0];

  $self->_set_conn( $conn );
  ## FIXME Try to register with remote, issue events
}

sub ircsock_connector_failure {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $connector = $_[ARG0];
  my ($op, $errno, $errstr) = @_[ARG1 .. ARG3];

  $self->_clear_conn if $self->_has_conn;
  ## FIXME failed to connect, retry?
}

sub ircsock_disconnect {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $str) = @_[ARG0, ARG1];
  ## FIXME clean up, emit
}

sub ircsock_input {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $ev) = @_[ARG0, ARG1];

  $self->emit( 'irc_'.lc($ev->command), $ev)
}


### Our handlers.

sub N_irc_001 {
  my (undef, $self) = splice @_, 0, 2;
  my $ev = ${ $_[0] };

  $self->state->nick_name(
    (split ' ', $ev->raw_line)[2]
  );
  
  EAT_NONE
}

sub N_irc_005 {
  my (undef, $self) = splice @_, 0, 2;
  my $ev = ${ $_[0] };
  ## FIXME parse ISUPPORT
  EAT_NONE
}

sub N_irc_nick {
  ## FIXME update our nick as-needed
  ##  Update our channels as-needed
  EAT_NONE
}

sub N_irc_notice {
  my (undef, $self) = splice @_, 0, 2;
  my $ev = ${ $_[0] };

  if (my $ctcp_ev = ctcp_extract($ev)) {
    $self->emit_now( 'irc_'.$ctcp_ev->command, $ctcp_ev );
    return EAT_ALL
  }
  
  EAT_NONE
}

sub N_irc_privmsg {
  my (undef, $self) = splice @_, 0, 2;
  my $ev = ${ $_[0] };

  if (my $ctcp_ev = ctcp_extract($ev)) {
    $self->emit_now( 'irc_'.$ctcp_ev->command, $ctcp_ev );
    return EAT_ALL
  }

  my $prefix = substr $ev->params->[0], 0, 1;
  if (grep {; $_ eq $prefix } ('#', '&', '+') ) {
    $self->emit_now( 'irc_public_msg', $ev )
  } else {
    $self->emit_now( 'irc_private_msg', $ev )
  }

  EAT_ALL
}

sub N_irc_topic {
  ## FIXME update state/channels
  EAT_NONE
}


### Public

sub connect_to {
  my $self = shift;
  $poe_kernel->post( $self->session_id, 'connect_to', @_ )
}

sub _connect_to {
  my ($kern, $self) = @_[KERNEL, OBJECT];

  ## FIXME Tell Backend to open a Connector
}

sub disconnect {
  my $self = shift;
  $poe_kernel->post( $self->session_id, 'disconnect', @_ )
}

sub _disconnect {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  $self->backend->disconnect( $self->conn->wheel->ID );
    if $self->has_conn and $self->conn->has_wheel;
}

sub send_raw_line {
  my ($self, $line) = @_;
  $self->send( ev(raw_line => $line) );
}

sub send {
  my $self = shift;
  $poe_kernel->post( $self->session_id, 'send', @_ )
}

sub _send {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  $self->backend->send( $_, $self->conn->wheel_id )
    for @_[ARG0 .. $#_];
}

## Sugar, and POE-dispatchable counterparts.
sub notice {
  my $self = shift;
  $poe_kernel->post( $self->session_id, 'notice', @_ )
}

sub _notice {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($target, @data) = @_[ARG0 .. $#_];
  $self->send(
    ev(
      command => 'notice',
      params  => [ $target, join ' ', @data ]
    )
  )
}

sub privmsg {
  my $self = shift;
  $poe_kernel->post( $self->session_id, 'privmsg', @_ )
}

sub _privmsg {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($target, @data) = @_[ARG0 .. $#_];
  $self->send(
    ev(
      command => 'privmsg',
      params  => [ $target, join ' ', @data ]
    )
  )
}

sub ctcp {
  my $self = shift;
  $poe_kernel->post( $self->session_id, 'ctcp', @_ )
}

sub _ctcp {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($type, $target, @data) = @_[ARG0 .. $#_];
  my $line = join ' ', uc($type), @data;
  my $quoted = ctcp_quote($line);
  $self->send(
    command => 'privmsg',
    params  => [ $target, $quoted ]
  )
}

sub mode {
  my $self = shift;
  $poe_kernel->post( $self->session_id, 'mode', @_ )
}

sub _mode {
  my ($kernel, $self)    = @_[KERNEL, OBJECT];
  my ($target, $modestr) = @_[ARG0, ARG1];
  ## FIXME take IRC::Mode(Change) objs also
  $self->send(
    ev(
      command => 'mode',
      params  => [ $target, $modestr ],
    )
  )
}

sub join {
  my $self = shift;
  $poe_kernel->post( $self->session_id, 'join', @_ )
}

sub _join {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  $self->send(
    ev(
      command => 'join',
      params  => [ $_[ARG0] ],
    )
  )
}

sub part {
  my $self = shift;
  $poe_kernel->post( $self->session_id, 'part', @_ )
}

sub _part {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($channel, $msg) = @_[ARG0, ARG1];
  $self->send(
    ev(
      command => 'part',
      params  => [ $channel, $msg ],
    )
  );
}


## FIXME figure out which emitted events should be munged
##   - public vs private messages?
##   - parse and record ISUPPORT ?
##   - channel state ? users, topics
##   - nick changes, look for ours ?


## FIXME
##  Hammer out a reasonably common interface between
##   a Client::Lite and Client::Pseudo
##   (shove interface into a Role::Interface::Client)

1;
