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

  Types
/;

extends 'IRC::Server::Pluggable::Emitter';


### Core bits.
## A Dispatcher instance to register with.
## FIXME need either:
##  - a Controller to tie a Protocol to a Dispatcher
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
with 'IRC::Server::Pluggable::Role::CaseMap';

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
          irc_ev_unknown_cmd_pass
          irc_ev_unknown_cmd_nick
          irc_ev_unknown_cmd_user
          irc_ev_unknown_cmd_server
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
          irc_ev_client_cmd_privmsg
          irc_ev_client_cmd_notice
      / ],
    ],
  },
);


sub BUILD {
  my ($self) = @_;

  ### FIXME set up object_states etc and $self->_start_emitter()
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
  ## FIXME
  ## Accepted connection to a listener
  ## ...  caching ->resolver backend?
  ## Issue async queries and preserve limited set of
  ##  cached replies we can try to pull from later
  ## If no callback in short timeout, disregard?
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
  ##  set up Peer obj
  ##  check if we should be setting up compressed_link
  ##  burst (event for this we can also trigger on compressed_link ?)
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

  ## FIXME
  ##  NICK/USER may come in indeterminate order
  ##  set up a User obj appropriately
  ##  need a method to create/modify these as-needed
  ##  see notes in PASS/USER
}

sub irc_ev_unknown_cmd_user {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $ev)     = @_[ARG0, ARG1];

  unless (@{$ev->params} && @{$ev->params} < 4) {
   ## FIXME
   ##  bad args, return numeric 461
  }

  ## USERNAME HOSTNAME SERVERNAME REALNAME
  my ($username, undef, $servername, $gecos) = @{$ev->params};

  ## FIXME
  ##  Need to set up a User obj if we don't have one from NICK
  ##  Need method(s) to check auth; incl. passwd auth if $conn->has_pass
  ##  Need registration method(s)
}

sub _construct_user_obj {

}

sub irc_ev_unknown_cmd_pass {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $ev)     = @_[ARG0, ARG1];

  unless (@{$ev->params}) {
    ## FIXME 461
  }

  ## RFC:
  ## A "PASS" command is not required for either client or server
  ## connection to be registered, but it must precede the server message
  ## or the latter of the NICK/USER combination.

  ## Set a pass() for this connection Wheel; we can check it later.
  $conn->set_pass( $ev->params->[0] )
    unless $conn->has_pass;
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
  ## Numeric from peer intended for a client of ours.
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $ev)     = @_[ARG0, ARG1];

  my $target_nick  = $ev->params->[0];
  my $this_user    = $self->users->by_nick($target_nick);

  return unless $this_user;

  my $target_wheel = $this_user->conn->wheel_id;

  $self->dispatcher->dispatch( $ev, $target_wheel )
}

## client_* handlers

sub irc_ev_client_cmd_privmsg {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $ev)     = @_[ARG0, ARG1];
}

sub irc_ev_client_cmd_notice {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $ev)     = @_[ARG0, ARG1];
}


## FIXME need an overridable way to format numeric replies

## FIXME need to handle unknown command input (_default handler?)


no warnings 'void';
q{
<Gilded> I'm only level 24 myself so I try to avoid the hard quests
 like "Job" or "Sex"
};


=pod

=cut
