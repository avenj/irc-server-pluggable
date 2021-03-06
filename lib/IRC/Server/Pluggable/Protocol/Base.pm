package IRC::Server::Pluggable::Protocol::Base;
use Defaults::Modern;

## Base class for Protocol sessions.
## Should primarily define attributes and start an Emitter.
## Protocol.pm should consume roles to form a basic Protocol.
##
## Most of these have overridable _build methods:
##
## has =>
##   autoloaded_plugins    ArrayRef
##                          Map plugin aliases to class names:
##                          [ $alias, $class ]
##
##   casemap               CaseMap
##                          rfc1459 || strict-rfc1459 || ascii
##
##   channels              ::IRC::Channels
##
##   channel_types         HashRef
##                          Map channel prefixes to classes defining
##                          channel behavior:
##                           '#' => $global_channel_class,
##
##   config                ::IRC::Config
##
##   dispatcher            ::Dispatcher
##
##   numeric               ::IRC::Numerics
##
##   peers                 ::IRC::Peers
##
##   users                 ::IRC::Users
##
##   version_string        Str

## Basic behavorial roles.
## Protocol.pm consumes others to form a useful basic TS Protocol.
## (These get consumed after attribs are defined; they shouldn't conflict.)
my $base_role_prefix = 'IRC::Server::Pluggable::Protocol::Role::';
my @base_roles = map { $base_role_prefix . $_ } qw/
  Send
  Disconnect

  Messages
  Motd
  Ping
  Stats
  Version
/;

use Carp;
use POE;

use IRC::Server::Pluggable qw/
  Constants
  Types

  Protocol::Plugin::Register
/;


use Moo;
use MooX::late;
use namespace::clean;

with 'MooX::Role::POE::Emitter';


### Core attribs

has autoloaded_plugins => (
  lazy    => 1,
  is      => 'ro',
  isa     => TypedArray[ArrayObj],
  coerce  => 1,
  writer  => 'set_autoloaded_plugins',
  builder => sub {
    my $prefix = 'IRC::Server::Pluggable::';
    array_of ArrayObj() => (
      ## [ NAME, CLASS, CONSTRUCTOR OPTS ], . . .
      ## .. if you're handling clients, you at least want Register:
      [ 'Register', $prefix . 'Protocol::Plugin::Register' ],
    )
  },
);

## A Dispatcher instance to register with.
## http://eris.cobaltirc.org/bug/1/14
has dispatcher => (
  lazy      => 1,
  is        => 'ro',
  isa       => InstanceOf['IRC::Server::Pluggable::Dispatcher'],
  writer    => 'set_dispatcher',
  predicate => 'has_dispatcher',
  builder   => sub {
    prefixed_new Dispatcher =>
     ()
    # FIXME construct backend_opts from $self->config
  },
  builder   => '_build_dispatcher',
);


## A IRC::Config object passed in.
has config => (
  required  => 1,
  is        => 'ro',
  writer    => 'set_config',
  isa       => InstanceOf['IRC::Server::Pluggable::IRC::Config'],
);


### IRCD-relevant attribs
has casemap => (
  lazy      => 1,
  is        => 'ro',
  isa       => CaseMap,
  writer    => 'set_casemap',
  predicate => 'has_casemap',
  builder   => sub { 'rfc1459' },
);
with 'IRC::Toolkit::Role::CaseMap';


has channel_types => (
  lazy      => 1,
  is        => 'ro',
  isa       => HashObj,
  coerce    => 1,
  writer    => 'set_channel_types',
  predicate => 'has_channel_types',
  builder   => '_build_channel_types',
);

method _build_channel_types {
  ## Map channel prefixes to a IRC::Channel subclass.
  ## These can control the behavior of specific channel types.
  ## FIXME Role should use these to determine what kind of
  ##  chan obj to construct
  my $prefix = 'IRC::Server::Pluggable::IRC::Channel::';
  hash(
    '&' => $prefix . 'Local',
    '#' => $prefix . 'Global',
  )
}


has version_string => (
  lazy       => 1,
  is         => 'ro',
  isa        => Str,
  predicate  => 'has_version_string',
  writer     => 'set_version_string',
  builder    => '_build_version_string',
);

method _build_version_string {
  my $vers = __PACKAGE__->VERSION || 'git';
  'irc-server-pluggable-' . $vers
}



### Collections.

## IRC::Channels
has channels => (
  lazy    => 1,
  is      => 'ro',
  isa     => InstanceOf['IRC::Server::Pluggable::IRC::Channels'],
  writer  => 'set_channels',
  builder => sub {
    my ($self) = @_;
    prefixed_new 'IRC::Channels' => (
      casemap => $self->casemap,
    )
  }
);


## IRC::Peers
has peers => (
  ## Map server names to Peer instances
  lazy    => 1,
  is      => 'ro',
  isa     => InstanceOf['IRC::Server::Pluggable::IRC::Peers'],
  writer  => 'set_peers',
  builder => sub { prefixed_new 'IRC::Peers' },
);


## IRC::Users
has users => (
  ## Map nicknames to User instances
  lazy    => 1,
  is      => 'ro',
  isa     => InstanceOf['IRC::Server::Pluggable::IRC::Users'],
  writer  => 'set_users',
  builder => sub { 
    my ($self) = @_;
    prefixed_new 'IRC::Users' => (
      casemap => $self->casemap
    )
  },
);


has numeric => (
  ## Numeric parser (IRC::Numerics)
  lazy    => 1,
  is      => 'ro',
  isa     => InstanceOf['IRC::Server::Pluggable::IRC::Numerics'],
  writer  => 'set_numeric',
  builder => sub { prefixed_new 'IRC::Numerics' },
);


with @base_roles;


method BUILD {
  ## FIXME set a DIE handler?
  ##  or turn off exception-catching globally somewheres?

  $self->set_object_states(
    [
      $self => {
        emitter_started   => '_emitter_started',
        dispatch          => '_dispatch',
        protocol_dispatch => '_dispatch',
      },

      ## Connectors and listeners
      ## These are dispatched from here.
      $self => [ qw/
          irc_ev_connection_idle

          irc_ev_peer_connected
          irc_ev_peer_compressed

          irc_ev_listener_created
          irc_ev_listener_open

          irc_ev_client_cmd
          irc_ev_peer_cmd
          irc_ev_unknown_cmd

          irc_ev_peer_numeric

          irc_ev_client_disconnected
          irc_ev_peer_disconnected
          irc_ev_unknown_disconnected

          irc_ev_register_complete
      / ],

      ## May have other object_states specified at construction time
      (
        $self->has_object_states ? @{ $self->object_states } : ()
      ),
    ],
  );

  $self->_start_emitter;
}

method DEMOLISH ($in_gd) {
  return if $in_gd;
  $self->_shutdown_emitter;
}

method _load_core_plugins {
  ## Array-of-arrays:
  ##  [ [ $alias, $class, @args ], [ $alias, $class, @args ] ]
  ## See autoloaded_plugins attrib
  for my $plugin_arr ($self->autoloaded_plugins->all) {
    unless (@$plugin_arr >= 2) {
      carp "autoloaded_plugins elements should have at least 2 values";
      next
    }

    my ($alias, $class, @params) = @$plugin_arr;

    try { require $class; 1 }
    catch { warn "Failed to load plugin module ($alias): $_"; () } 
      or next;

    $self->plugin_add( $alias => $class->new(@params) );
  }
}

sub _emitter_started {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## Load core plugins.
  ## (If your Protocol handles clients, you at least want
  ##  Protocol::Plugin::Register)
  $self->_load_core_plugins;

  ## If a Dispatcher wasn't passed in, we should force a _build:
  my $dispatcher = $self->dispatcher;

  ## Register with Dispatcher.
  $kernel->post( $dispatcher->session_id, 'subscribe' );
}


method protocol_dispatch ($event_name, @args) {
  ## This is a cheap implementation of internal dispatch,
  ## aimed at flexibly dispatching events synchronously
  ## within a Protocol and making it possible to return unknown cmd
  ## (421) as-needed.

  ## Try registered plugins first; they can skip dispatch early to 
  ## override Role-defined command handlers.
  ## Continue to $self if not eaten by a P_* handler.
  return DISPATCH_EATEN
    if $self->process( $event_name, @args ) == EAT_ALL;

  ## Try to handle via $self method dispatch.
  ## Return DISPATCH_UNKNOWN to caller if we lack the method.
  ## (This will often be an unknown command.)
  if ( $self->can($event_name) ) {
    $self->$event_name(@args);
    return DISPATCH_CALLED
  } else {
    return DISPATCH_UNKNOWN
  }
}

sub _dispatch {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $self->protocol_dispatch(@_[ARG0 .. $#_]);

  1
}


method object_is_local (Object $obj) {
  confess "Expected a User or Peer object but got $obj"
    unless $obj->can('has_conn') && $obj->can('route');
  $obj->has_conn ? $obj->route : ()
}

method user_is_local (UserObj $user) {
  $user->has_conn ? $user->route : ()
}

method peer_is_local (PeerObj $peer) {
  $peer->has_conn ? $peer->route : ()
}


method uid_or_full (UserObj $user, PeerObj $peer) {
  if ($peer->type eq 'TS' && $peer->type_version == 6) {
    return $user->uid if $user->has_uid
  }
  $user->full
}

method uid_or_nick (UserObj $user, PeerObj $peer) {
  if ($peer->type eq 'TS' && $peer->type_version == 6) {
    return $user->uid if $user->has_uid
  }
  $user->nick
}



sub irc_ev_peer_connected {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## FIXME
  ## A Connector is open.
  ## Dispatch an event; try to register with the remote end.
}

sub irc_ev_peer_compressed {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## FIXME
  ## Peer that needed compression is burstable.
}

sub irc_ev_listener_created {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## FIXME
  ## Not sure we actually care ourselves, but emit() it
}

sub irc_ev_listener_open {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $conn = $_[ARG0];

  return if $self->process( 'connection', $conn ) == EAT_ALL;

  ## Usually picked up by Plugin::Register, at least.
  $self->emit( 'connection', $conn );

  ## FIXME method to disconnect for host-based auth blocks?
  ##  not sure where the sanest place to hook that is ...
}

sub irc_ev_connection_idle {
  my ($kernel, $self) = @_;
  my $conn = $_[ARG0];

  $self->protocol_dispatch( 'conn_is_idle', $conn );
}

sub irc_ev_peer_disconnected {
  my ($self, $conn) = @_;
  ## A disconnected $conn has had its wheel cleared.
  ## FIXME squit this peer if we still have it in ->peers
}

sub irc_ev_client_disconnected {
  my ($self, $conn) = @_;
  ## FIXME quit this user if we still have it in ->users
}

sub irc_ev_unknown_disconnected {
  my ($self, $conn) = @_;

  ## FIXME emit event so registration bits know to clean up?
  ## FIXME wrap in Register role?
}

sub irc_ev_peer_numeric {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $event)  = @_[ARG0, ARG1];

  my $target_nick = $event->params->[0];
  my $target_user = $self->users->by_name($target_nick) || return;

  ## If this came off a TS6 peer, it should've carried a TS6 prefix:
  my $prefix_peer = $self->peers->by_id($conn->wheel_id)->has_sid ?
    $self->peers->by_sid($event->prefix)
    : $self->peers->by_name($event->prefix);

  $self->send_numeric( $event->command,
    target => $target_user,
    prefix => $prefix_peer,
    params => $event->params,
  );
}

sub irc_ev_client_cmd {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $event)  = @_[ARG0, ARG1];

  my $cmd = $event->command;

  my $user = $self->users->by_id($conn->wheel_id);

  my $disp = $self->protocol_dispatch( 'cmd_from_client_'.lc($cmd),
    $conn, $event, $user
  );

  if ($disp == DISPATCH_UNKNOWN) {
    $self->send_to_routes(
      $self->numeric->to_hash( 421,
        prefix => $self->config->server_name,
        params => [ uc($cmd) ],
        target => $user->nick,
      ),
      $conn->wheel_id
    );
  }
}

sub irc_ev_peer_cmd {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $event)  = @_[ARG0, ARG1];

  my $cmd = $event->command;

  my $peer = $self->peers->by_id($conn->wheel_id);

  $self->protocol_dispatch( 'cmd_from_peer_'.lc($cmd), $conn, $event, $peer );
}

sub irc_ev_unknown_cmd {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $event)  = @_[ARG0, ARG1];

  my $cmd = $event->command;

  $self->protocol_dispatch( 'cmd_from_unknown_'.lc($cmd), $conn, $event );
}

print q{
<Gilded> Arrh, gather around men, for I saw a user of the female variety
 on IRC once. 'Twas the year 2002, on a Magic the Gathering channel on ye
 olde QuakeNet. A fair wench did indeed join and then immediately part at
 the sight of all the unkempt neckbeards.
} unless caller; 1


=pod

=cut
