package IRC::Server::Pluggable::Protocol;
our $VERSION = 0;

## Base class for Protocol sessions.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use POE;

use IRC::Server::Pluggable qw/
  IRC::Channel
  IRC::Numerics
  IRC::Peer
  IRC::User

  Protocol::Plugin::Register

  Types
/;

extends 'IRC::Server::Pluggable::Emitter';


### Core bits.
## A Dispatcher instance to register with.
## http://eris.cobaltirc.org/dev/bugs/?do=details&task_id=14&project=1
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
  [ split '', 'iaow' ]
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
    protocol => $self,
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


has '_pending_reg' => (
  ## Keyed on $conn->wheel_id
  ## Values are hashes with keys 'nick', 'user', 'pass'
  lazy => 1,
  is   => 'ro',
  isa  => HashRef,
  default => sub { {} },
);



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
      [ qw/
          irc_ev_unknown_cmd_error
          irc_ev_unknown_cmd_nick
          irc_ev_unknown_cmd_pass
          irc_ev_unknown_cmd_server
          irc_ev_unknown_cmd_user
      / ],
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
      [ qw/
          irc_ev_peer_cmd_server
          irc_ev_peer_cmd_squit
          irc_ev_peer_numeric
      / ],
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
      [ qw/
          irc_ev_client_cmd_notice
          irc_ev_client_cmd_privmsg
      / ],
  ],
}

sub PROTO_ROLE_PREFIX () {
  'IRC::Server::Pluggable::Protocol::Role::
}

with 'IRC::Server::Pluggable::Role::CaseMap';


with PROTO_ROLE_PREFIX . 'Clients' ;
with PROTO_ROLE_PREFIX . 'Peers'   ;
with PROTO_ROLE_PREFIX . 'Ping'    ;
with PROTO_ROLE_PREFIX . 'Send'    ;

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

          irc_ev_register_complete
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


sub irc_ev_connection_idle {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## FIXME handle pings
}

sub irc_ev_peer_connected {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## FIXME
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

sub irc_ev_register_complete {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $hints)  = @_[ARG0, ARG1];

  ## Emitted from Plugin::Register when ident + host lookups finish.

  ## Hints hash has keys 'ident' and 'host'
  ##  (values will be undef if not found)
  ## Save to _pending_reg and see if we can register a User.
  $self->_pending_reg->{ $conn->wheel_id }->{authinfo} = $hints;
  $self->register_user_local($conn);
}

## unknown_* handlers
## These primarily deal with registration.

sub irc_ev_unknown_cmd_server {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $ev)     = @_[ARG0, ARG1];

  unless (@{$ev->params}) {
    my $output = $self->numeric->to_hash( 461,
      prefix => $self->config->server_name,
      target => '*',
      params => [ 'SERVER' ],
    );
    $self->send_to_route( $output, $conn->wheel_id );
    return
  }

  ## FIXME
  ##  check auth
  ##  check if peer exists
  ##  set $conn->is_peer
  ##  set up Peer obj, route() can default to wheel_id
  ##  check if we should be setting up compressed_link
  ##  burst (event for this we can also trigger on compressed_link ?)
  ##  clear from _pending_reg

  ## FIXME should a server care if Plugin::Register isn't done?
}

sub irc_ev_unknown_cmd_nick {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $ev)     = @_[ARG0, ARG1];

  unless (@{$ev->params}) {
    my $output = $self->numeric->to_hash( 461,
      prefix => $self->config->server_name,
      target => '*',
      params => [ 'NICK' ],
    );
    $self->send_to_route( $output, $conn->wheel_id );
    return
  }

  my $nick = $ev->params->[0];
  unless ( is_IRC_Nickname($nick) ) {
    my $output = $self->numeric->to_hash( 432,
      prefix => $self->config->server_name,
      target => '*',
      params => [ $nick ],
    );
    $self->send_to_route( $output, $conn->wheel_id );
    return
  }

  ## FIXME 433 if we have this nickname in state

  ## FIXME truncate if longer than max

  ## NICK/USER may come in indeterminate order
  ## Set up a $self->_pending_reg->{ $conn->wheel_id } hash entry.
  ## Call method to check current state.
  $self->_pending_reg->{ $conn->wheel_id }->{nick} = $nick;
  $self->register_user_local($conn);
}

sub irc_ev_unknown_cmd_user {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $ev)     = @_[ARG0, ARG1];

  unless (@{$ev->params} && @{$ev->params} < 4) {
    my $output = $self->numeric->to_hash(
      prefix => $self->config->server_name,
      target => '*',
      params => [ 'USER' ],
    );
    $self->send_to_route( $output, $conn->wheel_id );
    return
  }

  ## USERNAME HOSTNAME SERVERNAME REALNAME
  my ($username, undef, $servername, $gecos) = @{$ev->params};

  unless ( is_IRC_Username($username) ) {
    ## FIXME username validation
    ##  Reject/disconnect this user
    ##  (Need a rejection method perhaps)
  }

  $self->_pending_reg->{ $conn->wheel_id }->{user}  = $username;
  $self->_pending_reg->{ $conn->wheel_id }->{gecos} = $gecos || '';
  $self->register_user_local($conn);
}

sub irc_ev_unknown_cmd_pass {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $ev)     = @_[ARG0, ARG1];

  unless (@{$ev->params}) {
    my $output = $self->numeric->to_hash(
      prefix => $self->config->server_name,
      target => '*',
      params => [ 'PASS' ],
    );
  }

  ## RFC:
  ## A "PASS" command is not required for either client or server
  ## connection to be registered, but it must precede the server message
  ## or the latter of the NICK/USER combination.

  my $pass = $ev->params->[0];
  $self->_pending_reg->{ $conn->wheel_id }->{pass} = $pass;
}

sub irc_ev_unknown_cmd_error {
  ## FIXME
  ##  if this is a peer, call a handler event.
  ##  (may want/need notification)
}


## peer_* handlers

sub irc_ev_peer_cmd_ping {

}

sub irc_ev_peer_cmd_pong {

}

sub irc_ev_peer_cmd_server {

}

sub irc_ev_peer_cmd_squit {

}

sub irc_ev_peer_numeric {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $ev)     = @_[ARG0, ARG1];

  my $target_nick  = $ev->params->[0];
  my $target_user  = $self->users->by_name($target_nick);

  ## Numeric from peer intended for a client; route it.
  $self->send_to_route( $ev, $target_user->route );
}

## client_* handlers

sub irc_ev_client_cmd_privmsg {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $ev)     = @_[ARG0, ARG1];

  ## FIXME
  ## privmsg/notice will probably share a method/role

  ##  general pattern for cmds:
  ##   - plugin process()
  ##   - return if EAT
  ##   - execute our own normal actions
  ##   - emit() notification? depending on cmd
}

sub irc_ev_client_cmd_notice {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $ev)     = @_[ARG0, ARG1];
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
};

no warnings 'void';
q{
<Gilded> I'm only level 24 myself so I try to avoid the hard quests
 like "Job" or "Sex"
};


=pod

=cut
