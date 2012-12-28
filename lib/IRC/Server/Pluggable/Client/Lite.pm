package IRC::Server::Pluggable::Client::Lite;

use 5.12.1;
use Moo;
use POE;
use Carp 'confess';


use IRC::Server::Pluggable qw/
  Backend
  IRC::Event
  IRC::Filter
  Utils
  Utils::Parse::CTCP
  Types
/;

with 'IRC::Server::Pluggable::Role::Interface::Client';

with 'MooX::Role::POE::Emitter';
use MooX::Role::Pluggable::Constants;

### Required:
has server => (
  required  => 1,
  is        => 'ro',
  isa       => Str,
  writer    => 'set_server',
);

has nick => (
  required  => 1,
  is        => 'ro',
  isa       => Str,
  writer    => 'set_nick',
  ## FIXME auto-altnick
);
after 'set_nick' => sub {
  my ($self, $nick) = @_;
  if ($self->has_conn && $self->conn->has_wheel) {
    ## Try to change IRC nickname as well.
    $self->nick($nick)
  }
};

### Optional:

has bindaddr => (
  lazy      => 1,
  is        => 'ro',
  isa       => Defined,
  writer    => 'set_bindaddr',
  predicate => 'has_bindaddr',
  default   => sub {
    my ($self) = @_;
    return '::0' if $self->has_ipv6 and $self->ipv6;
    return '0.0.0.0'
  },
);

has ipv6 => (
  lazy      => 1,
  is        => 'ro',
  isa       => Bool,
  writer    => 'set_ipv6',
  predicate => 'has_ipv6',
  default   => sub { 0 },
);

has pass => (
  lazy      => 1,
  is        => 'ro',
  isa       => Str,
  writer    => 'set_pass',
  predicate => 'has_pass',
  clearer   => 'clear_pass',
  default   => sub { '' },
);

has port => (
  lazy      => 1,
  is        => 'ro',
  isa       => Num,
  writer    => 'set_port',
  predicate => 'has_port',
  default   => sub { 6667 },
);

has realname => (
  lazy      => 1,
  is        => 'ro',
  isa       => Str,
  writer    => 'set_realname',
  predicate => 'has_realname',
  default   => sub { __PACKAGE__ },
);

has reconnect => (
  lazy      => 1,
  is        => 'ro',
  isa       => Num,
  writer    => 'set_reconnect',
  default   => sub { 120 },
);

has username => (
  lazy      => 1,
  is        => 'ro',
  isa       => Str,
  writer    => 'set_username',
  predicate => 'has_username',
  default   => sub { 'ircplug' },
);

### Typically internal:
has backend => (
  lazy    => 1,
  is      => 'ro',
  isa     => InstanceOf['IRC::Server::Pluggable::Backend'],
  builder => '_build_backend',
);

sub _build_backend {
  my ($self) = @_;
  my $filter = prefixed_new( 'IRC::Filter' => 
    colonify => 0,
  );

  prefixed_new( 'Backend' =>
    filter_irc => $filter,
  )
}

has conn => (
  lazy      => 1,
  weak_ref  => 1,
  is        => 'ro',
  isa       => Defined,
  writer    => '_set_conn',
  predicate => '_has_conn',
  clearer   => '_clear_conn',
);


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
        emitter_started => '_emitter_started',
        connect     => '_connect',
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

  $self->_start_emitter;
}

sub _emitter_started {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  $kernel->post( $self->backend->spawn()->session_id, 'register' );
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

  my @pre;
  if ($self->has_pass && (my $pass = $self->pass)) {
    push @pre, ev(
      command => 'pass',
      params  => [
        $pass
      ],
    )
  }
  $self->send(
    @pre,
    ev(
      command => 'user',
      params  => [
        $self->username,
        '*', '*',
        $self->realname
      ],
    ),
    ev(
      command => 'nick',
      params  => [ $self->nick ],
    ),
  );

  $self->emit( 'irc_connected', $conn );
}

sub ircsock_connector_failure {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $connector = $_[ARG0];
  my ($op, $errno, $errstr) = @_[ARG1 .. ARG3];

  $self->_clear_conn if $self->_has_conn;

  $self->emit( 'irc_connector_failed', @_[ARG0 .. $#_] );
  
  $self->timer( $self->reconnect, 'connect')
    unless !$self->reconnect;
}

sub ircsock_disconnect {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $str) = @_[ARG0, ARG1];
  
  $self->_clear_conn if $self->_has_conn; 
 
  $self->emit( 'irc_disconnected', $str );
}

sub ircsock_input {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $ircev) = @_[ARG0, ARG1];

  return unless $ircev->command;
  $self->emit( 'irc_'.lc($ircev->command), $ircev)
}


### Our IRC-related handlers.

sub N_irc_ping {
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };

  $self->send(
    ev(
      command => 'pong',
      params  => [ @{ $ircev->params } ],
    )
  );

  EAT_NONE
}

sub N_irc_privmsg {
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };

  if (my $ctcp_ev = ctcp_extract($ircev)) {
    $self->emit_now( 'irc_'.$ctcp_ev->command, $ctcp_ev );
    return EAT_ALL
  }

  my $prefix = substr $ircev->params->[0], 0, 1;
  if (grep {; $_ eq $prefix } ('#', '&', '+') ) {
    $self->emit_now( 'irc_public_msg', $ircev )
  } else {
    $self->emit_now( 'irc_private_msg', $ircev )
  }

  EAT_ALL
}

sub N_irc_notice {
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };

  if (my $ctcp_ev = ctcp_extract($ircev)) {
    $self->emit_now( 'irc_'.$ctcp_ev->command, $ctcp_ev );
    return EAT_ALL
  }

  EAT_NONE
}



### Public

## Since the retval of yield() is $self, many of these can be chained:
##  $client->connect->join(@channels)->privmsg(
##    join(',', @channels),  'hello!'
##  );

sub connect {
  my $self = shift;
  $self->yield( 'connect', @_ )
}

sub _connect {
  my ($kern, $self) = @_[KERNEL, OBJECT];
  
  $self->backend->create_connector(
    remoteaddr => $self->server,
    remoteport => $self->port,
    (
      $self->has_ipv6 ? (ipv6 => $self->ipv6) : ()
    ),
    (
      $self->has_bindaddr ? (bindaddr => $self->bindaddr) : ()
    ),
  );
}

sub disconnect {
  my $self = shift;
  $self->yield( 'disconnect', @_ )
}

sub _disconnect {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $message = $_[ARG0];
  $self->backend->send(
    ev(
      command => 'quit',
      params  => [ $message ],
    )
  );
  $self->backend->disconnect( $self->conn->wheel->ID )
    if $self->has_conn and $self->conn->has_wheel;
}

sub send_raw_line {
  my ($self, $line) = @_;
  $self->send( ev(raw_line => $line) );
}

sub send {
  my $self = shift;
  $self->yield( 'send', @_ )
}

sub _send {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  for my $outev (@_[ARG0 .. $#_]) {
    $self->process( 'outgoing', $outev );
    $self->backend->send( $outev, $self->conn->wheel_id )
  }
}

## Sugar, and POE-dispatchable counterparts.
sub notice {
  my $self = shift;
  $self->yield( 'notice', @_ )
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
  $self->yield( 'privmsg', @_ )
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
  $self->yield( 'ctcp', @_ )
}

sub _ctcp {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($type, $target, @data) = @_[ARG0 .. $#_];
  my $line = join ' ', uc($type), @data;
  my $quoted = ctcp_quote($line);
  $self->send(
    ev(
      command => 'privmsg',
      params  => [ $target, $quoted ]
    )
  )
}

sub mode {
  my $self = shift;
  $self->yield( 'mode', @_ )
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
  $self->yield( 'join', @_ )
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
  $self->yield( 'part', @_ )
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

1;

=pod

=head1 NAME

IRC::Server::Pluggable::Client::Lite - Tiny POE IRC client and base class

=head1 SYNOPSIS

FIXME

=head1 DESCRIPTION

A light-weight, pluggable IRC client library.

No state is maintained; the B<Client::Lite> client library provides a
minimalist interface to IRC and serves as a base class for stateful Client
classes.


FIXME

=head2 new

FIXME

=head2 stop

  $irc->stop;

Disconnect, stop the Emitter, and purge the plugin pipeline.

=head2 IRC Methods

IRC-related methods can be called via normal method dispatch or sent as a POE
event:

  ## These are equivalent:
  $irc->send( $ircevent );
  $irc->yield( 'send', $ircevent );
  $poe_kernel->post( $irc_session_id, 'send', $ircevent );

Methods that dispatch to IRC return C<$self>, so they can be chained:

  $irc->connect->join(@channels)->privmsg(
    join(',', @channels),
    'hello there!'
  );

=head3 connect

  $irc->connect;

Attempt an outgoing connection.

=head3 disconnect

  $irc->disconnect($message);

Quit IRC and shut down the wheel.

=head3 send

  use IRC::Server::Pluggable qw/ IRC::Event /;
  $irc->send(
    ev(
      command => 'oper',
      params  => [ $user, $passwd ],
    )
  );

  ## ... or a raw HASH:
  $irc->send(
    {
      command => 'oper',
      params  => [ $user, $passwd ],
    }
  )

  ## ... or a raw line:
  $irc->send_raw_line('PRIVMSG avenj :some things');

Use C<send()> to send an L<IRC::Server::Pluggable::IRC::Event> or a compatible
HASH; this method will also take a list of events in either of those formats.

Use C<send_raw_line()> to send a single raw IRC line. This is rarely a good
idea; L<IRC::Server::Pluggable::Backend> provides an IRCv3-capable filter.

=head3 privmsg

  $irc->privmsg( $target, $string );

Sends a PRIVMSG to the specified target.

=head3 notice

  $irc->notice( $target, $string );

Sends a NOTICE to the specified target.

=head3 ctcp

  $irc->ctcp( $target, $type, @params );

Encodes and sends a CTCP B<request> to the target.
(To send a CTCP B<reply>, send a L</notice> that has been quoted via
L<IRC::Server::Pluggable::Utils::Parse::CTCP/"ctcp_quote">.)

=head3 mode

FIXME

=head3 join

  $irc->join( $channel );

Attempts to join the specified channel.

=head3 part

  $irc->part( $channel, $message );

Attempts to leave the specified channel with an optional PART message.
=head1 IRC Events

All IRC events are emitted as 'irc_$cmd' e.g. 'irc_005' (ISUPPORT) or
'irc_mode' with a few notable exceptions:

=head3 irc_private_message

FIXME

=head3 irc_public_message

FIXME

=head3 irc_ctcp

FIXME

=head3 irc_ctcpreply

FIXME

=head1 SEE ALSO

L<IRC::Server::Pluggable>

L<IRC::Server::Pluggable::Backend>

L<IRC::Server::Pluggable::IRC::Event>

L<IRC::Server::Pluggable::IRC::Filter>

L<MooX::Role::POE::Emitter>

L<MooX::Role::Pluggable>

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
