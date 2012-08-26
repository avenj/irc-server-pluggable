package IRC::Server::Pluggable::Protocol;

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
## FIXME need either:
##  - a Controller to tie a Protocol to a Dispatcher
##    (probably a bin/ frontend could just do this)
##  - a spawn method carrying backend_opts to Dispatcher
has 'dispatcher' => (
  required  => 1,
  is        => 'ro',
  writer    => 'set_dispatcher',
  isa       => sub {
    is_Object($_[0])
      and $_[0]->isa('IRC::Server::Pluggable::Dispatcher')
      or confess "$_[0] is not a IRC::Server::Pluggable::Dispatcher"
  },
);

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
  default   => sub { 'rfc1459' },
);

has 'channel_types' => (
  lazy      => 1,
  is        => 'ro',
  isa       => HashRef,
  writer    => 'set_channel_types',
  predicate => 'has_channel_types',
  default   => sub {
    ## FIXME map channel prefixes to a IRC::Channel subclass?
    ##  These can control the behavior of specific channel types.
    '#' => 'IRC::Server::Pluggable::IRC::Channel::Global',
    '&' => 'IRC::Server::Pluggable::IRC::Channel::Local',
  },
);

has 'prefix_map' => (
  lazy      => 1,
  isa       => HashRef,
  is        => 'ro',
  predicate => 'has_prefix_map',
  writer    => 'set_prefix_map',
  default   => sub {
  ## Map PREFIX= to channel mode characters.
  ## (These also compose the valid status mode list)
    {
      '@' => 'o',
      '+' => 'v',
    },
  },
);

has 'valid_channel_modes' => (
  lazy      => 1,
  isa       => HashRef,
  is        => 'ro',
  predicate => 'has_valid_channel_modes',
  writer    => 'set_valid_channel_modes',
  default   => sub {
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
    },
  },
);

has 'valid_user_modes' => (
  lazy      => 1,
  isa       => ArrayRef,
  is        => 'ro',
  predicate => 'has_valid_user_modes',
  writer    => 'set_valid_user_modes',
  default   => sub { [ split '', 'iaow' ] },
);

has 'version_string' => (
  lazy       => 1,
  isa        => Str,
  is         => 'ro',
  predicate  => 'has_version_string',
  writer     => 'set_version_string',
  default    => sub { ref $_[0] },
);


### Collections.
has 'channels' => (
  lazy    => 1,
  is      => 'ro',
  writer  => 'set_channels',
  isa     => sub {
    is_Object($_[0])
      and $_[0]->isa('IRC::Server::Pluggable::IRC::Channels')
      or confess "$_[0] is not a IRC::Server::Pluggable::IRC::Channels"
  },
  default => sub {
    my ($self) = @_;

    IRC::Server::Pluggable::IRC::Channels->new(
      casemap => $self->casemap,
    )
  },
);

has 'peers' => (
  lazy   => 1,
  is     => 'ro',
  writer => 'set_peers',
  isa    => sub {
    is_Object($_[0])
      and $_[0]->isa('IRC::Server::Pluggable::IRC::Peers')
      or confess "$_[0] is not a IRC::Server::Pluggable::IRC::Peers"
  },
  default => sub {
    my ($self) = @_;

    IRC::Server::Pluggable::IRC::Peers->new(
    );
  }
);

has 'users' => (
  ## Map nicknames to objects
  ## (IRC::Users objects have conn() attribs containing the Backend::Wheel)
  lazy    => 1,
  is      => 'ro',
  writer  => 'set_users',
  isa     => sub {
    is_Object($_[0])
      and $_[0]->isa('IRC::Server::Pluggable::IRC::Users')
      or confess "$_[0] is not a IRC::Server::Pluggable::IRC::Users"
  },
  default => sub {
    my ($self) = @_;

    IRC::Server::Pluggable::IRC::Users->new(
      casemap => $self->casemap,
    )
  },
);

has '_pending_reg' => (
  ## Keyed on $conn->wheel_id
  ## Values are hashes with keys 'nick', 'user', 'pass'
  lazy => 1,
  is   => 'ro',
  isa  => HashRef,
  default => sub { {} },
);

### Helpers.
has 'numeric' => (
  ## Numeric parser.
  lazy    => 1,
  is      => 'ro',
  writer  => 'set_numeric',
  isa     => sub {
    is_Object($_[0])
      and $_[0]->isa('IRC::Server::Pluggable::IRC::Numerics')
      or confess "$_[0] is not a IRC::Server::Pluggable::IRC::Numerics"
  },
  default => sub {
    IRC::Server::Pluggable::IRC::Numerics->new()
  },
);


### States.
has 'states_unknown_cmds' => (
  lazy    => 1,
  is      => 'ro',
  isa     => ArrayRef,
  writer  => 'set_states_unknown_cmds',
  default => sub {
    my ($self) = @_;
    [ $self => [ qw/
          irc_ev_unknown_cmd_error
          irc_ev_unknown_cmd_nick
          irc_ev_unknown_cmd_pass
          irc_ev_unknown_cmd_server
          irc_ev_unknown_cmd_user
      / ],
    ],
  },
);

has 'states_peer_cmds' => (
  lazy    => 1,
  is      => 'ro',
  isa     => ArrayRef,
  writer  => 'set_states_peer_cmds',
  default => sub {
    my ($self) = @_;
    [ $self => [ qw/
          irc_ev_peer_cmd_server
          irc_ev_peer_cmd_squit
      / ],
    ],
  },
);

has 'states_client_cmds' => (
  lazy    => 1,
  is      => 'ro',
  isa     => ArrayRef,
  writer  => 'set_states_client_cmds',
  default => sub {
    my ($self) = @_;
    [ $self => [ qw/
          irc_ev_client_cmd_notice
          irc_ev_client_cmd_privmsg
      / ],
    ],
  },
);


with 'IRC::Server::Pluggable::Role::CaseMap';
with 'IRC::Server::Pluggable::Role::Routing';


sub BUILD {
  my ($self) = @_;

  $self->set_object_states(
    [
      $self => {
        'emitter_started' => '_emitter_started',
      },

      ## Connectors and listeners:
      $self => [ qw/
          irc_ev_connection_idle

          irc_ev_peer_connected
          irc_ev_peer_compressed

          irc_ev_listener_created
          irc_ev_listener_open

          irc_ev_register_complete
      / ],

      ## Command handlers:
      ( @{ $self->states_unknown_cmds } ),
      ( @{ $self->states_peer_cmds    } ),
      ( @{ $self->states_client_cmds  } ),

      ## May have other object_states specified at construction time:
      (
        $self->has_object_states ? @{ $self->object_states } : ()
      ),
    ],
  );

  $self->_start_emitter;
}

sub _emitter_started {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## Load Protocol::Plugin::Register
  $self->plugin_add( 'Register',
    IRC::Server::Pluggable::Protocol::Plugin::Register->new
  );

  ## Register with Dispatcher.
  $kernel->post( $self->dispatcher->session_id, 'register' );
}


sub irc_ev_connection_idle {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## FIXME handle pings
}

sub irc_ev_peer_connected {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

}

sub irc_ev_peer_compressed {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

}

sub irc_ev_listener_created {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

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

sub irc_ev_register_complete {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $hints)  = @_[ARG0, ARG1];

  ## Hints hash has keys 'ident' and 'host'
  ## Hints hash elements will be undef if not found
  ## Save to _pending_reg and see if we can register this.
  $self->_pending_reg->{ $conn->wheel_id }->{authinfo} = $hints;
  $self->_try_user_reg($conn);
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
    $self->dispatcher->dispatch( $output, $conn->wheel_id );
    return
  }

  ## FIXME
  ##  check auth
  ##  check if peer exists
  ##  set up Peer obj / set $conn->is_peer
  ##  check if we should be setting up compressed_link
  ##  burst (event for this we can also trigger on compressed_link ?)
  ##  clear from _pending_reg
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
    $self->dispatcher->dispatch( $output, $conn->wheel_id );
    return
  }

  my $nick = $ev->params->[0];
  unless ( is_IRC_Nickname($nick) ) {
    my $output = $self->numeric->to_hash( 432,
      prefix => $self->config->server_name,
      target => '*',
      params => [ $nick ],
    );
    $self->dispatcher->dispatch( $output, $conn->wheel_id );
    return
  }

  ## FIXME 433 if we have this nickname in state

  ## FIXME truncate if longer than max

  ## NICK/USER may come in indeterminate order
  ## Set up a $self->_pending_reg->{ $conn->wheel_id } hash entry.
  ## Call method to check current state.
  $self->_pending_reg->{ $conn->wheel_id }->{nick} = $nick;
  $self->_try_user_reg($conn);
}

sub _try_user_reg {
  my ($self, $conn) = @_;

  my $pending_ref = $self->_pending_reg->{ $conn->wheel_id } || return;

  unless ($conn->has_wheel) {
    delete $self->_pending_reg->{ $conn->wheel_id };
    return
  }

  ## Jump out if registration is incomplete.
  return unless defined $pending_ref->{nick}
         and    defined $pending_ref->{user}
         ## authinfo has keys 'host', 'ident'
         ## undef if these lookups were unsuccessful
         and    $pending_ref->{authinfo};

  $conn->is_client(1);

  ## FIXME auth check methods:
  ##  - check pass if present
  ##  - plugin process a preregister event for ban hooks, etc
  ## FIXME need a sane disconnect/clear method

  ## FIXME create User obj
  ##  - use {authinfo}->{ident} and {host} if available
  ##  - use _pending_reg->{user} if ident not avail
  ##  - use peeraddr if host not available

  ## FIXME send 001..004 numerics, lusers, motd, default mode if configured
  ##  dispatch registered event

  delete $self->_pending_reg->{ $conn->wheel_id };
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
    $self->dispatcher->dispatch( $output, $conn->wheel_id );
    return
  }

  ## USERNAME HOSTNAME SERVERNAME REALNAME
  my ($username, undef, $servername, $gecos) = @{$ev->params};

  ## FIXME username validation?

  $self->_pending_reg->{ $conn->wheel_id }->{user}  = $username;
  $self->_pending_reg->{ $conn->wheel_id }->{gecos} = $gecos || '';
  $self->_try_user_reg($conn);
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

  ## Numeric from peer intended for a client
  $self->dispatcher->dispatch(
    $ev,
    $self->route_to_user($target_nick)
  )
}

## client_* handlers

sub irc_ev_client_cmd_privmsg {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $ev)     = @_[ARG0, ARG1];

  ## FIXME
  ## privmsg/notice will probably share a method

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
    carp "_default expected Backend::Wheel and Backend::Event objects";
    return
  }

  ## Already handled:
  return if $ev->handled;

  ## FIXME not handled, dispatch unknown cmd
  ## FIXME  ... do servers need anything special?
};


## FIXME
## User/Peer should be created for both local and remote registrations
## User/Peer should have either a conn() or a route() at construction time
## A route() should be the name of a local Peer that has_conn()

no warnings 'void';
q{
<Gilded> I'm only level 24 myself so I try to avoid the hard quests
 like "Job" or "Sex"
};


=pod

=cut
