package IRC::Server::Pluggable::Client::Lite;

use 5.12.1;
use Moo;
use POE;
use Carp 'confess';


use MooX::Struct -rw,
  State => [ 
    qw/
      %channels
      $isupport
      nick_name
      server_name
    /,
    ## Abuse MooX::Struct a bit to get easy uc_irc():
    get_channel => sub {
      my ($self, $channel) = @_;
      confess "Expected a channel name" unless defined $channel;
      my $casemap = $self->isupport->casemap;
      $channel = uc_irc($channel, $casemap);
      $self->channels->{$channel}
    },
    get_status_prefix => sub {
      my ($self, $channel, $nick) = @_;
      confess "Expected a channel and nickname"
        unless defined $channel and defined $nick;
      my $casemap = $self->isupport->casemap;
      ($channel, $nick) = map {; uc_irc($_, $casemap) } ($channel, $nick);
      $self->channels->{$channel}->nicknames->{$nick}
    },
  ],

  Channel => [ qw/
      %nicknames
      $topic
  / ],

  Topic => [ qw/
    set_by!
    +set_at
    topic!
  / ],

  ISupport => [ qw/
    casemap!
  / ],
;

## Factory method for subclasses.
sub _create_struct {
  my ($self, $type) = splice @_, 0, 2;
  my $obj;
  for (lc $type) {
    $obj = Channel->new(@_)  when 'channel';
    $obj = ISupport->new(@_) when 'isupport';
    $obj = State->new(@_)    when 'state';
    $obj = Topic->new(@_)    when 'topic';
    confess "cannot create struct - unknown type $type"
  }
  $obj
}

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

has state => (
  lazy    => 1,
  is      => 'ro',
  isa     => Object,
  clearer => '_clear_state',
  writer  => '_set_state',
  builder => '_build_state',
);

sub _build_state { 
    State->new(
      channels    => {},
      nick_name   => '',
      server_name => '',
      isupport    => ISupport->new( casemap => 'rfc1459' ),
    )
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
  
  my $connected_to = $self->state->server_name;
  $self->_set_state( $self->_build_state );
  
  $self->emit( 'irc_disconnected', $connected_to, $str );
}

sub ircsock_input {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $ev) = @_[ARG0, ARG1];

  return unless $ev->command;
  $self->emit( 'irc_'.lc($ev->command), $ev)
}


### Our handlers.

sub N_irc_ping {
  my (undef, $self) = splice @_, 0, 2;
  my $ev = ${ $_[0] };

  $self->send(
    ev(
      command => 'pong',
      params  => [ @{ $ev->params } ],
    )
  );

  EAT_NONE
}

sub N_irc_001 {
  my (undef, $self) = splice @_, 0, 2;
  my $ev = ${ $_[0] };

  $self->state->server_name( $ev->prefix );

  $self->state->nick_name(
    (split ' ', $ev->raw_line)[2]
  );

  EAT_NONE
}

sub N_irc_005 {
  my (undef, $self) = splice @_, 0, 2;
  my $ev = ${ $_[0] };

  my %isupport;
  my @params = @{ $ev->params };
  ## Drop target nickname, trailing 'are supported by ..':
  shift @params;
  pop   @params;

  for my $item (@params) {
    my ($key, $val) = split /=/, $item, 2;
    $key = lc $key;
    if (defined $val) {
      $isupport{$key} = $val
    } else {
      $isupport{$key} = -1;
    }
  }

  for my $key (keys %isupport) {
    $self->state->isupport->EXTEND(
      -rw => $key
    ) unless $self->state->isupport->can($key);
    $self->state->isupport->$key( $isupport{$key} )
  }

  EAT_NONE
}

sub N_irc_332 {
  ## Topic
  my (undef, $self) = splice @_, 0, 2;
  my $ev = ${ $_[0] };

  my (undef, $target, $topic) = @{ $ev->params };

  my $casemap = $self->isupport('casemap');
  $target     = uc_irc( $target, $casemap );

  my $chan_obj = $self->state->channels->{$target};
  $chan_obj->topic->topic( $topic );

  EAT_NONE
}

sub N_irc_333 {
  ## Topic setter & TS
  my (undef, $self) = splice @_, 0, 2;
  my $ev = ${ $_[0] };
  my (undef, $target, $setter, $ts) = @{ $ev->params };
 
  my $casemap = $self->isupport('casemap');
  $target     = uc_irc( $target, $casemap );

  my $chan_obj = $self->state->channels->{$target};
  $chan_obj->topic->set_at( $ts );
  $chan_obj->topic->set_by( $setter );

  EAT_NONE
}

sub N_irc_352 {
  ## WHOREPLY
  ##  FIXME update nickname(s) for applicable channel(s)
  ##   add status prefixes?
}

sub N_irc_nick {
  my (undef, $self) = splice @_, 0, 2;
  my $ev = ${ $_[0] };
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

sub N_irc_mode {
  my (undef, $self) = splice @_, 0, 2;
  my $ev = ${ $_[0] };
  my ($target, $modestr, @params) = @{ $ev->params };

  my $casemap  = $self->isupport('casemap');
  $target      = uc_irc( $target, $casemap );
  my $chan_obj = $self->state->channels->{$target} || return EAT_NONE;

  my(@always, @whenset);
  if (my $cmodes = $self->isupport('chanmodes')) {
    my ($list, $always, $whenset) = split /,/, $cmodes;
    push @always,  split('', $list), split('', $always);
    push @whenset, split '', $whenset;
  }

  my %prefixes = (
    'o' => '@',
    'h' => '%',
    'v' => '+',
  );

  PREFIX: {
    if (my $sup_prefix = $self->isupport('prefix')) {
      my (undef, $modes, $symbols) = split /[\()]/, $sup_prefix;
      last PREFIX unless $modes and $symbols
        and length $modes == length $symbols;
      $modes   = [ split '', $modes ];
      $symbols = [ split '', $symbols ];
      @prefixes{@$modes} = @$symbols
    }
  }

  my $mode_hash = mode_to_hash( $modestr,
    params       => [ @params ],
    ( @always   ? (param_always => \@always)  : () ),
    ( @whenset  ? (param_set    => \@whenset) : () ),
  );
 
  MODE_ADD: for my $char (keys %{ $mode_hash->{add} }) {
    next MODE_ADD unless exists $prefixes{$char}
      and ref $mode_hash->{add}->{$char} eq 'ARRAY';
    my $param = $mode_hash->{add}->{$char}->[0];
    my $this_user;
    unless ($this_user = $chan_obj->nicknames->{ uc_irc($param, $casemap) }) {
      warn "Mode change for nonexistant user $param";
      next MODE_ADD
    }
    push @$this_user, $prefixes{$char}
  }

  MODE_DEL: for my $char (keys %{ $mode_hash->{del} }) {
    next MODE_DEL unless exists $prefixes{$char}
      and ref $mode_hash->{del}->{$char} eq 'ARRAY';
    my $param = $mode_hash->{del}->{$char}->[0];
    my $this_user;
    unless ($this_user = $chan_obj->nicknames->{ uc_irc($param, $casemap) }) {
      warn "Mode change for nonexistant user $param";
      next MODE_DEL
    }
    @$this_user = grep {; $_ ne $prefixes{$char} } @$this_user
  }

  EAT_NONE
}

sub N_irc_join {
  my (undef, $self) = splice @_, 0, 2;
  my $ev = ${ $_[0] };

  my ($nick, $user, $host) = parse_user( $ev->prefix );

  my $casemap = $self->isupport('casemap');
  my $target  = uc_irc( $ev->params->[0], $casemap );
  $nick       = uc_irc( $nick, $casemap );

  if ( eq_irc($nick, $self->state->nick_name, $casemap) ) {
    ## Us. Add new Channel struct.
    $self->state->channels->{$target} = Channel->new(
      nicknames => {},
      topic     => Topic->new(
        set_by => '',
        set_at => 0,
        topic  => '',
      ),
    );
    ## ... and request a WHO
    $self->send(
      ev(
        command => 'who',
        params  => [ $ev->params->[0] ],
      )
    );
  }

  my $chan_obj = $self->state->channels->{$target};
  $chan_obj->nicknames->{$nick} = [];

  EAT_NONE
}

sub N_irc_part {
  my (undef, $self) = splice @_, 0, 2;
  my $ev = ${ $_[0] };
  
  my ($nick)  = parse_user( $ev->prefix );
  my $casemap = $self->isupport('casemap');
  my $target  = uc_irc( $ev->params->[0], $casemap );
  $nick       = uc_irc( $nick, $casemap );
  
  delete $self->state->channels->{$target};
  
  EAT_NONE
}

sub N_irc_quit {
  my (undef, $self) = splice @_, 0, 2;
  my $ev = ${ $_[0] };

  my ($nick)  = parse_user( $ev->prefix );
  my $casemap = $self->isupport('casemap');
  $nick       = uc_irc( $nick, $casemap );

  while (my ($channel, $chan_obj) = each %{ $self->state->channels }) {
    delete $chan_obj->nicknames->{$nick};
  }

  EAT_NONE
}

sub N_irc_topic {
  my (undef, $self) = splice @_, 0, 2;
  my $ev = ${ $_[0] };
  
  my ($nick, $user, $host) = parse_user( $ev->prefix );
  my ($target, $str) = @{ $ev->params };

  my $casemap = $self->isupport('casemap');
  $target     = uc_irc( $target, $casemap );
 
  my $chan_obj = $self->state->channels->{$target};
  $chan_obj->topic( Topic->new(
      set_at => time(),
      set_by => $ev->prefix,
      topic  => $str,
    )
  );

  EAT_NONE
}


### Public

sub isupport {
  my ($self, $key) = @_;
  $key = lc($key // confess "Expected a key");
  return unless $self->state->isupport->can($key);
  $self->state->isupport->$key
}

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
  $self->backend->send( $_, $self->conn->wheel_id )
    for @_[ARG0 .. $#_];
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
    command => 'privmsg',
    params  => [ $target, $quoted ]
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

IRC::Server::Pluggable::Client::Lite - Lightweight POE IRC client library

=head1 SYNOPSIS

FIXME

=head1 DESCRIPTION

A light-weight, pluggable IRC client library.

FIXME

=head2 new

FIXME

=head2 stop

  $irc->stop;

Disconnect, stop the Emitter, and purge the plugin pipeline.

=head2 IRC Methods

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

=head3 isupport

  my $casemap = $irc->isupport('casemap');

Returns ISUPPORT values, if they are available.

If the value is a KEY=VALUE pair (e.g. 'MAXMODES=4'), the VALUE portion is
returned.

A value that is a simple boolean (e.g. 'CALLERID') will return '-1'.

=head2 State

The State struct provides some very basic state information that can be
queried via accessor methods:

=head3 nick_name

  my $current_nick = $irc->state->nick_name;

Returns the client's current nickname.

=head3 server_name

  my $current_serv = $irc->state->server_name;

Returns the server's announced name.

=head3 get_channel

  my $chan_st = $irc->state->get_channel($channame);

If the channel is found, returns a Channel struct with the following accessor
methods:

=head4 nicknames

  my @users = keys %{ $chan_st->nicknames };

A HASH whose keys are the users present on the channel.

If a user has status modes, the values are an ARRAY of status prefixes (f.ex,
o => '@', v => '+', ...)

=head4 status_prefix_for

FIXME

=head4 topic

  my $topic_st = $chan_st->topic;
  my $topic_as_string = $topic_st->topic();

The Topic struct provides information about the current channel topic via
accessors:

=over

=item *

B<topic> is the actual topic string

=item *

B<set_at> is the timestamp of the topic change

=item *

B<set_by> is the topic's setter

=back

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

L<IRC::Server::Pluggable::IRC::Filter>

L<MooX::Role::POE::Emitter>

L<MooX::Role::Pluggable>

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
