package IRC::Server::Pluggable::Protocol::Role::Register;
use Defaults::Modern;

## A role defining user/server registration.

use POE;

use IRC::Server::Pluggable qw/
  Constants
  IRC::Event
  IRC::User
  Types
/;


use Moo::Role;
with 'IRC::Server::Pluggable::Role::Interface::IRCd';

has '_r_pending_reg' => (
  ## Keyed on $conn->wheel_id
  ##  Values are hashes
  ##  Clients have keys 'nick', 'user', 'pass
  lazy    => 1,
  is      => 'ro',
  isa     => HashRef,
  default => sub { {} },
);


method __register_user_create_obj {
  ## Define me in consuming (sub)class to change the class constructed
  ## for a User.
  prefixed_new('IRC::User' => @_)
}

method __register_peer_create_obj {
  prefixed_new('IRC::Peer' => @_)
}

method __register_user_ready ($conn) {
  ## Called if a local user may be ready to complete registration.
  ## Returns the pending user hash if NICK, USER, and identd/hostname
  ## have all been retrieved.

  my $pending_ref = $self->_r_pending_reg->{ $conn->wheel_id } || return;

  unless ( $conn->has_wheel ) {
    ## Connection's wheel has disappeared; this user may have been 
    ## disconnected, and its wheel cleared in Backend.
    delete $self->_r_pending_reg->{ $conn->wheel_id };
    return
  }

  return unless defined $pending_ref->{nick}
         and    defined $pending_ref->{user}
         ## ->{authinfo} has keys 'host' , 'ident'
         ## Values are undef if these lookups were unsuccessful
         and    $pending_ref->{authinfo};

  $pending_ref
}

method _register_user_local (Object $conn) {
  ## Has this Backend::Connect finished registration?
  my $pending_ref = $self->__register_user_ready($conn);
  return unless $pending_ref;

  delete $self->_r_pending_reg->{ $conn->wheel_id };

  $conn->is_client(1);

  ## Auth check.
  ## FIXME overridable / pluggable method instead
  if (defined $pending_ref->{pass}) {
    ## FIXME
    ##  figure out ->config attribs for local user auth config
  }

  my $nickname = $pending_ref->{nick};
  my $realname = $pending_ref->{gecos};
  my $username = $pending_ref->{authinfo}->{ident}
                 || '~' . $pending_ref->{user};

  my $hostname = $pending_ref->{authinfo}->{host}
                 || $conn->peeraddr;

  my $server = $self->config->server_name;

  my $user = $self->__register_user_create_obj(
    conn     => $conn,
    nick     => $nickname,
    user     => $username,
    host     => $hostname,
    realname => $realname,
    server   => $server,
    ## FIXME could set default modes() here
    ##  then just relay $user->modes() after lusers/motd, below
  );

  ## FIXME method to check for bans also, subclasses are faster
  ## Ban-type plugins can grab P_user_registering
  ## Banned users should be disconnected at the backend and the
  ## event should be eaten.
  return if
    $self->process( 'user_registering', $user ) == EAT_ALL;

  ## Add to our IRC::Users collection:
  $self->users->add( $user );

  ## Dispatch 001 .. 004 numerics, lusers, motd, default mode(s)

  my $net_name = $self->config->network_name;

  $self->send_to_routes(
    {
      prefix  => $server,
      command => '001',
      params  => [
        $nickname,
        "Welcome to the $net_name Internet Relay Chat network $nickname"
      ],
    },
    $conn->wheel_id
  );

  $self->send_to_routes(
    {
      prefix  => $server,
      command => '003',
      params  => [
        $nickname,
        $server,
        $self->version_string,
        ## FIXME build mode lists to send
      ],
    },
    $conn->wheel_id
  );

  ## FIXME VERSION / ISUPPORT [005] (dispatch cmd handler event) ?

  ## Dispatch LUSERS
  $self->protocol_dispatch( 'cmd_from_client_lusers', $conn,
    IRC::Server::Pluggable::IRC::Event->new(
      command => 'LUSERS',
    )
  );

  ## Dispatch MOTD
  $self->protocol_dispatch( 'cmd_from_client_motd', $conn,
    IRC::Server::Pluggable::IRC::Event->new(
      command => 'MOTD',
    )
  );

  ## FIXME see notes about default modes in object creation above

  $self->emit( 'user_registered', $user );

  $user
}


method _register_user_remote {
  ## FIXME figure out sane args for this; these are bursted users

  ## FIXME create a User obj

  ## FIXME burst methods

  ## FIXME remote User objs need a route() specifying wheel_id for
  ## next-hop peer; i.e., the peer that introduced the user to us
  ##  take next-hop Peer/conn obj as arg, pull wheel_id
}


## Our event handlers.

sub irc_ev_register_complete {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $hints)  = @_[ARG0, ARG1];

  ## Emitted from Plugin::Register when ident + host lookups finish.

  ## May have disconnected before lookups in plugin finished:
  return unless exists $self->_r_pending_reg->{ $conn->wheel_id };

  ## Hints hash has keys 'ident' and 'host'
  ##  (values will be undef if not found)
  ## Save to _r_pending_reg and see if we can register a User.
  $self->_r_pending_reg->{ $conn->wheel_id }->{authinfo} = $hints;
  $self->_register_user_local($conn);
}

method cmd_from_unknown_server ($conn, $event) {
  delete $self->_r_pending_reg->{ $conn->wheel_id };

  unless (@{$event->params}) {
    $self->send_to_routes(
      $self->numeric->to_hash( 461,
        prefix => $self->config->server_name,
        target => '*',
        params => [ 'SERVER' ],
      ),
      $conn->wheel_id
    );
    return
  }

  ## FIXME check if TS server?
  ##  attrib to mark a Peer accordingly?

  ## FIXME
  ##  check auth (and args?)
  ##  check if peer exists
  my $intro_name = $event->params->[0];
  my $peer;
  if ($peer = $self->peers->by_name($intro_name)) {
    ## FIXME peer exists
    ## call disconnect method
    ## send ERROR
    ## kill any pending user registrations belonging to this server
  }

  $conn->is_peer(1);

  ## set up Peer obj, route() can default to conn->wheel_id
  $peer = $self->__register_peer_create_obj(
    conn => $conn,
    name => $intro_name,
  );

  ## add to ->peers
  $self->peers->add($peer);

  ## FIXME
  ##  check if we should be setting up compressed_link
  ##  burst (event for this we can also trigger on compressed_link ?)

  ## FIXME should a server care if Plugin::Register isn't done?
}


method cmd_from_unknown_error {
  ## FIXME
  ## do nothing if this conn isn't registering as a peer
}

method cmd_from_unknown_nick ($conn, $event) {
  unless (@{$event->params}) {
    $self->send_to_routes(
      $self->numeric->to_hash( 461,
        prefix => $self->config->server_name,
        target => '*',
        params => [ 'NICK' ],
      ),
      $conn->wheel_id
    );
    return
  }

  my $nick = $event->params->[0];
  unless ( is_IRC_Nickname($nick) ) {
    $self->send_to_routes(
      $self->numeric->to_hash( 432,
        prefix => $self->config->server_name,
        target => '*',
        params => [ $nick ],
      ),
      $conn->wheel_id
    return
  }

  ## FIXME 433 if we have this nickname in state

  ## FIXME truncate if longer than max

  ## NICK/USER may come in indeterminate order
  ## Set up a $self->_r_pending_reg->{ $conn->wheel_id } hash entry.
  ## Call method to check current state.
  $self->_r_pending_reg->{ $conn->wheel_id }->{nick} = $nick;
  $self->_register_user_local($conn);
}


method cmd_from_unknown_user ($conn, $event) {
  unless (@{$event->params} && @{$event->params} < 4) {
    $self->send_to_routes(
      $self->numeric->to_hash( 461,
        prefix => $self->config->server_name,
        target => '*',
        params => [ 'USER' ],
      )
      $conn->wheel_id
    );
    return
  }

  ## USERNAME HOSTNAME SERVERNAME REALNAME
  my ($username, undef, $servername, $gecos) = @{$event->params};

  ## FIXME preserve servername as well?
  ##  Not really used in modern IRCDs, but we report it on cobaltirc

  unless ( is_IRC_Username($username) ) {
    ## FIXME username validation
    ##  Reject/disconnect this user
    ##  (Need a rejection method)
    ## http://eris.cobaltirc.org/dev/bugs/?task_id=32&project=1
  }

  ## FIXME methods to provide interface to pending_reg
  $self->_r_pending_reg->{ $conn->wheel_id }->{user}  = $username;
  $self->_r_pending_reg->{ $conn->wheel_id }->{gecos} = $gecos || '';
  $self->_register_user_local($conn);
}

method cmd_from_unknown_pass ($conn, $event) {
  unless (@{$event->params}) {
    $self->send_to_routes(
      $self->numeric->to_hash( 461,
        prefix => $self->config->server_name,
        target => '*',
        params => [ 'PASS' ],
      ),
      $conn->wheel_id
    );
    return
  }

  ## RFC:
  ##   A "PASS" command is not required for either client or server
  ##   connection to be registered, but it must precede the server
  ##   message or the latter of the NICK/USER combination.
  ##
  ## Preserve PASS for later checking by _register_user_local.

  my $pass = $event->params->[0];
  $self->_r_pending_reg->{ $conn->wheel_id }->{pass} = $pass;
}


## FIXME call burst methods to sync up after registration?
##  or call() burst handlers via Protocol?


1;
