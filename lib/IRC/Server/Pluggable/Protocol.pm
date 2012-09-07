package IRC::Server::Pluggable::Protocol;
our $VERSION = 0;

## Base class for Protocol sessions.
## Should primarily define attributes and start an Emitter.
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
##   states_client_cmds    ArrayRef (POE state map)
##   states_peer_cmds      ArrayRef (POE state map)
##   states_unknown_cmds   ArrayRef (POE state map)
##
##   users                 ::IRC::Users
##
##   valid_channel_modes   HashRef
##                          See _build_valid_channel_modes
##
##   version_string        Str
##
## Consumes Protocol::Role:: roles.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use POE;

use IRC::Server::Pluggable qw/
  Constants

  IRC::Channel
  IRC::Numerics
  IRC::Peer
  IRC::User

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

  IRC::Server::Pluggable::IRC::Channels->new(
    casemap => $self->casemap,
  )
}


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
  IRC::Server::Pluggable::IRC::Peers->new
}


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
  ## Numeric parser.
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
    IRC::Server::Pluggable::IRC::Numerics->new
}



### States.
has 'states_unknown_cmds' => (
  lazy    => 1,
  is      => 'ro',
  isa     => ArrayRef,
  writer  => 'set_states_unknown_cmds',
  builder => '_build_states_unknown_cmds',
);

sub _build_states_unknown_cmds {
  my ($self) = @_;
  [ $self =>
      [
        ## Handled in Protocol::Role::Register:
        qw/
          irc_ev_unknown_cmd_nick
          irc_ev_unknown_cmd_pass
          irc_ev_unknown_cmd_server
          irc_ev_unknown_cmd_user
          irc_ev_register_complete
        /,
      ],
  ]
}


has 'states_peer_cmds' => (
  lazy    => 1,
  is      => 'ro',
  isa     => ArrayRef,
  writer  => 'set_states_peer_cmds',
  builder => '_build_states_peer_cmds',
);

sub _build_states_peer_cmds {
  my ($self) = @_;
  [ $self =>

      [
        ## Protocol::Role::Messages:
        qw/
          irc_ev_peer_cmd_privmsg
          irc_ev_peer_cmd_notice
        /,

        ## Protocol::Role::Peers:
        qw/
          irc_ev_peer_numeric
          irc_ev_peer_cmd_server
          irc_ev_peer_cmd_squit
        /,

        ## Protocol::Role::Ping:
        qw/
          irc_ev_peer_cmd_ping
          irc_ev_peer_cmd_pong
        /,
      ],
  ],
}


has 'states_client_cmds' => (
  lazy    => 1,
  is      => 'ro',
  isa     => ArrayRef,
  writer  => 'set_states_client_cmds',
  builder => '_build_states_client_cmds',
);

sub _build_states_client_cmds {
  my ($self) = @_;
  [ $self =>
      [
        ## Protocol::Role::Messages:
        qw/
          irc_ev_client_cmd_privmsg
          irc_ev_client_cmd_notice
        /,

        ## Protocol::Role::Ping:
        qw/
          irc_ev_client_cmd_ping
          irc_ev_client_cmd_pong
        /,
      ],
  ],
}


### Roles, composed in order.

sub PROTO_ROLE_PREFIX () {
  'IRC::Server::Pluggable::Protocol::Role::'
}

with 'IRC::Server::Pluggable::Role::CaseMap';

with PROTO_ROLE_PREFIX . 'Send'     ;
with PROTO_ROLE_PREFIX . 'Messages' ;
with PROTO_ROLE_PREFIX . 'Register' ;
with PROTO_ROLE_PREFIX . 'Clients'  ;
with PROTO_ROLE_PREFIX . 'Peers'    ;
with PROTO_ROLE_PREFIX . 'Ping'     ;
with PROTO_ROLE_PREFIX . 'Burst'    ;


sub BUILD {
  my ($self) = @_;

  $self->set_object_states(
    [
      $self => {
        'emitter_started' => '_emitter_started',
      },

      ## Connectors and listeners
      ## These are dispatched from here.
      $self => [ qw/
          irc_ev_connection_idle

          irc_ev_peer_connected
          irc_ev_peer_compressed

          irc_ev_listener_created
          irc_ev_listener_open
      / ],

      ## Command handlers:
      @{ $self->states_client_cmds  },
      @{ $self->states_peer_cmds    },
      @{ $self->states_unknown_cmds },

      ## May have other object_states specified at construction time:
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

## FIXME
##  Spec out which of the handlers below actually belong in a
##  Role. Try to keep this file small.

sub irc_ev_unknown_cmd_error {
  ## FIXME
  ## Received ERROR from the remote end
  ## if this isn't a conn in process of registering as a peer
  ##  we should do nothing
  ## needs to hook in with SERVER registration
  ## may belong in the same Role as SERVER registration bits
}



around '_emitter_default' => sub {
  my $orig = shift;

  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($event, $args)  = @_[ARG0, ARG1];

  ## Our super's behavior:
  unless ($event =~ /^_/ || $event =~ /^emitter_(?:started|stopped)$/) {
    return if $self->process( $event, @$args ) == EAT_ALL
  }

  ## Not interested if it's not a client/peer cmd:
  return unless $event =~ /^irc_ev_(?:client|peer)_cmd_/;

  my ($conn, $ev) = @$args;
  unless (is_Object($conn) && is_Object($ev)) {
    carp "_default expected Backend::Connect and Backend::Event objects",
         "got $conn and $ev";
    return
  }

  ## Already handled:
  return if $ev->handled;

  ## FIXME not handled, dispatch unknown cmd
  ## FIXME  ... do servers need anything special?

  ## FIXME switch to method dispatch passing wheel / event objects?
  ##  worth a ponder; may be easier plus we can process() all the time
  ##  rather than hard-coded methods?
  ##  would also mean irc_ev_* is more of a private/reserved ns
};

no warnings 'void';
q{
<Gilded> I'm only level 24 myself so I try to avoid the hard quests
 like "Job" or "Sex"
};


=pod

=cut
