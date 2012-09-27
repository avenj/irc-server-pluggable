package IRC::Server::Pluggable::Protocol::Base;
our $VERSION = 0;

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
##   valid_channel_modes   HashRef
##                          See _build_valid_channel_modes
##
##   version_string        Str

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use POE;

use IRC::Server::Pluggable qw/
  Constants

  Protocol::Plugin::Register

  Types
/;


use namespace::clean -except => 'meta';


extends 'IRC::Server::Pluggable::Emitter';


### Core bits.
## A Dispatcher instance to register with.
## http://eris.cobaltirc.org/bug/1/14
has 'dispatcher' => (
  lazy      => 1,
  is        => 'ro',
  writer    => 'set_dispatcher',
  predicate => 'has_dispatcher',
  builder   => '_build_dispatcher',
  isa       => sub {
    is_Object($_[0])
      and $_[0]->isa('IRC::Server::Pluggable::Dispatcher')
      or confess "$_[0] is not a IRC::Server::Pluggable::Dispatcher"
  },
);

sub _build_dispatcher {
  my ($self) = @_;

  require IRC::Server::Pluggable::Dispatcher;

  IRC::Server::Pluggable::Dispatcher->new(
    ## FIXME construct backend_opts from $self->config
  );
}


## A IRC::Config object passed in.
has 'config' => (
  required  => 1,
  is        => 'ro',
  writer    => 'set_config',
  isa       => sub {
    is_Object($_[0])
      and $_[0]->isa('IRC::Server::Pluggable::IRC::Config')
      or confess "$_[0] is not a IRC::Server::Pluggable::IRC::Config"
  },
);


### IRCD-relevant attribs
has 'casemap' => (
  lazy      => 1,
  is        => 'ro',
  isa       => CaseMap,
  writer    => 'set_casemap',
  predicate => 'has_casemap',
  builder   => '_build_casemap',
);

sub _build_casemap {  'rfc1459'  }


has 'channel_types' => (
  lazy      => 1,
  is        => 'ro',
  isa       => HashRef,
  writer    => 'set_channel_types',
  predicate => 'has_channel_types',
  builder   => '_build_channel_types',
);

sub _build_channel_types {
  ## Map channel prefixes to a IRC::Channel subclass.
  ## These can control the behavior of specific channel types.
  {
    '&' => 'IRC::Server::Pluggable::IRC::Channel::Local',
    '#' => 'IRC::Server::Pluggable::IRC::Channel::Global',
  }
}

## FIXME valid_channel_modes should maybe move to Channels.pm?
has 'valid_channel_modes' => (
  lazy      => 1,
  isa       => HashRef,
  is        => 'ro',
  predicate => 'has_valid_channel_modes',
  writer    => 'set_valid_channel_modes',
  builder   => '_build_valid_channel_modes',
);

sub _build_valid_channel_modes {
    ## ISUPPORT CHANMODES=1,2,3,4
    ## Channel modes fit in four categories:
    ##  'LIST'     -> Modes that manipulate list values
    ##  'PARAM'    -> Modes that require a parameter
    ##  'SETPARAM' -> Modes that only require a param when set
    ##  'SINGLE'   -> Modes that take no parameters
    {
      LIST     => [ 'b' ],
      PARAM    => [ 'k' ],
      SETPARAM => [ 'l' ],
      SINGLE   => [ split '', 'imnpst' ],
    }
}


has 'valid_user_modes' => (
  lazy      => 1,
  isa       => ArrayRef,
  is        => 'ro',
  predicate => 'has_valid_user_modes',
  writer    => 'set_valid_user_modes',
  builder   => '_build_valid_user_modes',
);

sub _build_valid_user_modes {
  ## Override to add valid user modes.
  [ split '', 'iaows' ]
}


has 'version_string' => (
  lazy       => 1,
  isa        => Str,
  is         => 'ro',
  predicate  => 'has_version_string',
  writer     => 'set_version_string',
  builder    => '_build_version_string',
);

sub _build_version_string {
  my ($self) = @_;
  ref $self .'-'. $VERSION
}



### Collections.

## IRC::Channels
has 'channels' => (
  lazy    => 1,
  is      => 'ro',
  writer  => 'set_channels',
  builder => '_build_channels',
  isa     => sub {
    is_Object($_[0])
      and $_[0]->isa('IRC::Server::Pluggable::IRC::Channels')
      or confess "$_[0] is not a IRC::Server::Pluggable::IRC::Channels"
  },
);

sub _build_channels {
  my ($self) = @_;

  require IRC::Server::Pluggable::IRC::Channels;

  IRC::Server::Pluggable::IRC::Channels->new(
    casemap => $self->casemap,
  )
}


## IRC::Peers
has 'peers' => (
  ## Map server names to Peer instances
  lazy    => 1,
  is      => 'ro',
  writer  => 'set_peers',
  builder => '_build_peers',
  isa     => sub {
    is_Object($_[0])
      and $_[0]->isa('IRC::Server::Pluggable::IRC::Peers')
      or confess "$_[0] is not a IRC::Server::Pluggable::IRC::Peers"
  },
);

sub _build_peers {
  require IRC::Server::Pluggable::IRC::Peers;

  IRC::Server::Pluggable::IRC::Peers->new
}


## IRC::Users
has 'users' => (
  ## Map nicknames to User instances
  lazy    => 1,
  is      => 'ro',
  writer  => 'set_users',
  builder => '_build_users',
  isa     => sub {
    is_Object($_[0])
      and $_[0]->isa('IRC::Server::Pluggable::IRC::Users')
      or confess "$_[0] is not a IRC::Server::Pluggable::IRC::Users"
  },
);

sub _build_users {
  my ($self) = @_;

  require IRC::Server::Pluggable::IRC::Users;

  IRC::Server::Pluggable::IRC::Users->new(
      casemap => $self->casemap,
  )
}



### Helpers.
has 'autoloaded_plugins' => (
  lazy    => 1,
  is      => 'ro',
  isa     => ArrayRef,
  writer  => 'set_autoloaded_plugins',
  builder => '_build_autoloaded_plugins',
);

sub _build_autoloaded_plugins {
  ## Build array-of-arrays specifiny
  my $prefix = 'IRC::Server::Pluggable::';
  [
    ## [ NAME, CLASS, CONSTRUCTOR OPTS ], . . .

    ## If you're handling clients, you at least want Register:
    [ 'Register', $prefix . 'Protocol::Plugin::Register' ],

  ],
}


has 'numeric' => (
  ## Numeric parser (IRC::Numerics)
  lazy    => 1,
  is      => 'ro',
  writer  => 'set_numeric',
  builder => '_build_numeric',
  isa     => sub {
    is_Object($_[0])
      and $_[0]->isa('IRC::Server::Pluggable::IRC::Numerics')
      or confess "$_[0] is not a IRC::Server::Pluggable::IRC::Numerics"
  },
);

sub _build_numeric {
  require IRC::Server::Pluggable::IRC::Numerics;

  IRC::Server::Pluggable::IRC::Numerics->new
}



### States.
has 'extra_states' => (
  lazy    => 1,
  is      => 'ro',
  isa     => ArrayRef,
  writer  => 'set_extra_states',
  clearer => 'clear_extra_states',
  builder => '_build_extra_states',
  predicate => 'has_extra_states',
);

sub _build_extra_states {
  my ($self) = @_;
  [ $self =>
      [
        qw/
          irc_ev_register_complete

          irc_ev_peer_numeric

          irc_ev_client_cmd
          irc_ev_peer_cmd
          irc_ev_unknown_cmd
        /,
      ],
  ]
}


## Basic behavorial roles.
## Protocol.pm consumes others to form a useful basic TS Protocol.
with 'IRC::Server::Pluggable::Role::CaseMap';

with 'IRC::Server::Pluggable::Protocol::Role::Send';
with 'IRC::Server::Pluggable::Protocol::Role::Disconnect';

with 'IRC::Server::Pluggable::Protocol::Role::Motd';
with 'IRC::Server::Pluggable::Protocol::Role::Ping';



sub BUILD {
  my ($self) = @_;

  $self->set_object_states(
    [
      $self => {
        'emitter_started' => '_emitter_started',
        'dispatch'        => '_dispatch',
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
      / ],

      ## Predefined in the base class, but subs could tweak if they like:
      (
        $self->has_extra_states ? @{ $self->extra_states }   : ()
      ),

      ## May have other object_states specified at construction time
      ## (attrib inherited from Emitter)
      (
        $self->has_object_states ? @{ $self->object_states } : ()
      ),
    ],
  );

  $self->_start_emitter;
}

sub _load_core_plugins {
  my ($self) = @_;

  ## Array-of-arrays:
  ##  [ [ $alias, $class, @args ], [ $alias, $class, @args ] ]
  ## See autoloaded_plugins attrib
  for my $plugin_arr (@{ $self->autoloaded_plugins }) {
    unless (ref $plugin_arr eq 'ARRAY') {
      carp "autoloaded_plugins element not an ARRAY: $plugin_arr";
      next
    }
    unless (@$plugin_arr >= 2) {
      carp "autoloaded_plugins elements should have at least 2 values";
      next
    }

    my ($alias, $class, @params) = @$plugin_arr;
    $self->plugin_add( $alias,
      $class->new(@params)
    );
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
  $kernel->post( $dispatcher->session_id, 'register' );
}


sub irc_ev_peer_connected {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## FIXME
  ## A Connector is open.
  ## Try to register with the remote end.
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

  $self->dispatch( 'conn_is_idle', $conn );
}


sub irc_ev_peer_numeric {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $event)  = @_[ARG0, ARG1];

  my $target_nick = $event->params->[0];
  my $target_user = $self->users->by_name($target_nick) || return;

  $self->send_to_route( $event, $target_user->route );
}

sub irc_ev_client_cmd {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $event)  = @_[ARG0, ARG1];

  my $cmd = $event->command;

  my $user = $self->users->by_id($conn->wheel_id);

  my $disp = $self->dispatch( 'cmd_from_client_'.lc($cmd),
    $conn, $event, $user
  );

  if ($disp eq 'UNKNOWN') {
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

  $self->dispatch( 'cmd_from_peer_'.lc($cmd), $conn, $event, $peer );
}

sub irc_ev_unknown_cmd {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $event)  = @_[ARG0, ARG1];

  ## FIXME
  ## validate ascii?
  ## ... hmm, we *know* we have a command, right? maybe not so much.
  my $cmd = $event->command;

  $self->dispatch( 'cmd_from_unknown_'.lc($cmd), $conn, $event );
}

sub dispatch {
  my ($self, $event_name, @args) = @_;

  ## Dispatch:
  ## -> Try to handle via P_$event_name plugin handlers
  ##    Return 'ATE' if P_* handler returns EAT_ALL
  ## -> If not eaten, try to call $event_name method on $self
  ##    (brought in by Roles, usually)
  ##    Return 'CALL' if we called this method via $self
  ## -> Otherwise if not eaten and no method to call,
  ##    return 'UNKNOWN' to caller
  ##    Caller can return 421 (unknown command), for example.

  return 'ATE'
    if $self->process( $event_name, @args ) == EAT_ALL;

  if ( $self->can($event_name) ) {
    $self->$event_name(@args);
    return 'CALL'
  } else {
    return 'UNKNOWN'
  }

  1
}

sub _dispatch {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $self->dispatch(@_[ARG0 .. $#_]);

  1
}


no warnings 'void';
q{
<Gilded> Arrh, gather around men, for I saw a user of the female variety
 on IRC once. 'Twas the year 2002, on a Magic the Gathering channel on ye
 olde QuakeNet. A fair wench did indeed join and then immediately part at
 the sight of all the unkempt neckbeards.
};


=pod

=cut
