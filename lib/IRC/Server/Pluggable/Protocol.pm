package IRC::Server::Pluggable::Protocol;

## Base class for Protocol sessions.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use POE;

use IRC::Server::Pluggable qw/
  IRC::Channel
  IRC::Peer
  IRC::User

  Types
/;

extends 'IRC::Server::Pluggable::Emitter';


has 'dispatcher' => (
  lazy => 1,

  is  => 'ro',

  predicate => 'has_dispatcher',
  writer    => 'set_dispatcher',

  default => sub {
    my ($self) = @_;

    require IRC::Server::Pluggable::Dispatcher;

    IRC::Server::Pluggable::Dispatcher->new(
      ## FIXME requires backend_opts to construct all the way down
      ##  may make more sense to just require a Dispatcher?
      ##  then we'd need a Controller to tie it all together ...
    )
  },
);


### IRCD-relevant attribs
has 'casemap' => (
  lazy => 1,

  is  => 'rw',
  isa => CaseMap,

  default => sub { 'rfc1459' },
);

with 'IRC::Server::Pluggable::Role::CaseMap';


has 'channel_types' => (
  lazy => 1,

  is  => 'rw',
  isa => HashRef,

  default => sub {
    ## FIXME map channel prefixes to a IRC::Channel subclass?
    ##  These can control the behavior of specific channel types.
    '#' => 'IRC::Server::Pluggable::IRC::Channel::Global',
    '&' => 'IRC::Server::Pluggable::IRC::Channel::Local',
  },
);

has 'max_chan_length' => (
  lazy => 1,

  is  => 'rw',
  isa => Int,

  default => sub { 30 },
);

has 'max_nick_length' => (
  lazy => 1,

  is  => 'rw',
  isa => Int,

  default => sub { 9 },
);

has 'max_msg_targets' => (
  lazy => 1,

  is  => 'rw',
  isa => Int,

  default => sub { 4 },
);

has 'network_name' => (
  lazy => 1,

  is  => 'rw',
  isa => Str,

  default => sub { 'NoNetworkDefined' },
);

has 'prefix_map' => (
  ## Map PREFIX= to channel mode characters.
  ## (These also compose the valid status mode list)
  lazy => 1,

  isa => HashRef,
  is  => 'rw',

  default => sub {
    {
      '@' => 'o',
      '+' => 'v',
    },
  },
);

has 'valid_channel_modes' => (
  lazy => 1,

  isa => HashRef,
  is  => 'rw',

  default => sub {
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
  lazy => 1,

  isa => ArrayRef,
  is  => 'rw',

  default => sub {
    [ split '', 'iaow' ]
  },
);

has 'version_string' => (
  lazy => 1,

  isa => Str,
  is  => 'rw',

  default => sub { ref $_[0] },
);

has 'users' => (
  ## Map nicknames to objects
  ## (IRC::Users objects have conn() attribs containing the Backend::Wheel)
  lazy => 1,

  is => 'ro',

  isa => sub {
    is_Object($_[0])
      and $_[0]->isa('IRC::Server::Pluggable::IRC::Users')
      or confess "$_[0] is not a IRC::Server::Pluggable::IRC::Users"
  },

  default => sub {
    my ($self) = @_;

    require IRC::Server::Pluggable::IRC::Users;

    IRC::Server::Pluggable::IRC::Users->new(
      protocol => $self,
    )
  },
);

has 'channels' => (
  lazy => 1,

  is => 'ro',

  isa => sub {
    is_Object($_[0])
      and $_[0]->isa('IRC::Server::Pluggable::IRC::Channels')
      or confess "$_[0] is not a IRC::Server::Pluggable::IRC::Channels"
  },

  default => sub {
    my ($self) = @_;

    require IRC::Server::Pluggable::IRC::Channels;

    IRC::Server::Pluggable::IRC::Channels->new(
      protocol => $self,
    )
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

      $self => [
        ## Connectors and listeners:
        qw/
          irc_ev_connection_idle
          irc_ev_peer_connected
          irc_ev_peer_compressed
          irc_ev_listener_created
        /,

        ## peer_* cmds:
        ## FIXME
#        qw/
#          irc_ev_peer_cmd_
#        /,

        ## client_* cmds:
        ## FIXME
#        qw/
#          irc_ev_client_
#        /,

        ## unknown_* cmds:
        ## FIXME
#        qw/
#          irc_ev_unknown_cmd_
#        /,
      ],

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


## unknown_* handlers
## These primarily deal with registration.

sub irc_ev_unknown_cmd_server {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $ev)     = @_[ARG0, ARG1];

  unless (@{$ev->params}) {
    ## FIXME 461
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
    ## FIXME 461
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
  ##  Set up a User obj if we don't have one from PASS / NICK ?
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

  ## Set a pass() for this connection Wheel.
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



## FIXME need an overridable way to format numeric replies

## FIXME need to handle unknown command input (_default handler?)


no warnings 'void';
q{
<Gilded> I'm only level 24 myself so I try to avoid the hard quests
 like "Job" or "Sex"
};


=pod

=cut
