package IRC::Server::Pluggable::Protocol::Role::Register;

## A role defining user/server registration.

use 5.12.1;
use Carp;

use Moo::Role;
use strictures 1;

use IRC::Server::Pluggable qw/
  Constants

  IRC::User
/;


requires qw/
  config

  users
  peers

  numeric

  process
  emit
  emit_now

  send_to_routes
/;

has '_r_pending_reg' => (
  ## Keyed on $conn->wheel_id
  ##  Values are hashes
  ##  Clients have keys 'nick', 'user', 'pass
  lazy    => 1,
  is      => 'ro',
  isa     => HashRef,
  default => sub { {} },
);


sub _register_user_create_obj {
  my ($self, %params) = @_;
  ## Define me in consuming (sub)class to change the class constructed
  ## for a User.
  IRC::Server::Pluggable::IRC::User->new(%params)
}


sub register_user_local {
  my ($self, $conn) = @_;

  ## Has this Backend::Connect finished registration?
  my $pending_ref = $self->__register_user_ready($conn);
  return unless $pending_ref;

  delete $self->_r_pending_reg->{ $conn->wheel_id };

  $conn->is_client(1);

  ## Auth check.
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

  my $user = $self->_register_user_create_obj(
    conn     => $conn,
    nick     => $nickname,
    user     => $username,
    host     => $hostname,
    realname => $realname,
    server   => $server,
    ## FIXME could set default modes() here
    ##  then just relay $user->modes() after lusers/motd, below
  );

  ## Ban-type plugins can grab P_user_registering
  ## Banned users should be disconnected at the backend and the
  ## event should be eaten.
  return if
    $self->process( 'user_registering', $user ) == EAT_ALL;

  ## Add to our IRC::Users collection:
  $self->users->add( $user );

  ## FIXME
  ##  -> dispatch 001 .. 004 numerics, lusers, motd, default mode

  my $net_name = $self->config->network_name;

  $self->send_to_routes(
    {
      prefix  => $server,
      command => '001',
      params  => [
        $nickname,
        "Welcome to the $net_name Internet Relay Chat network $nick"
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

  ## FIXME ISUPPORT [005] (dispatch cmd handler event)

  ## FIXME LUSERS (dispatch cmd handler event)

  ## FIXME MOTD   (dispatch cmd handler event)

  ## FIXME see notes about default modes in object creation above

  $self->emit( 'user_registered', $user );

  $user
}

sub __register_user_ready {
  my ($self, $conn) = @_;

  ## Called if a local user may be ready to complete registration.
  ## Returns the pending user hash if NICK, USER, and identd/hostname
  ## have all been retrieved.

  my $pending_ref = $self->_r_pending_reg->{ $conn->wheel_id } || return;

  unless ( $conn->has_wheel ) {
    ## Connection's wheel has disappeared.
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

sub register_user_remote {
  ## FIXME figure out sane args for this; these are bursted users

  ## Figure out what belongs in Burst role
  ## FIXME remote User objs need a route() specifying wheel_id for
  ## next-hop peer; i.e., the peer that introduced the user to us
  ##  take next-hop Peer/conn obj as arg, pull wheel_id
}


## Our event handlers.

sub irc_ev_register_complete {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $hints)  = @_[ARG0, ARG1];

  ## Emitted from Plugin::Register when ident + host lookups finish.

  ## Hints hash has keys 'ident' and 'host'
  ##  (values will be undef if not found)
  ## Save to _r_pending_reg and see if we can register a User.
  $self->_r_pending_reg->{ $conn->wheel_id }->{authinfo} = $hints;
  $self->register_user_local($conn);
}


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
  ##  clear from _r_pending_reg

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
  ## Set up a $self->_r_pending_reg->{ $conn->wheel_id } hash entry.
  ## Call method to check current state.
  $self->_r_pending_reg->{ $conn->wheel_id }->{nick} = $nick;
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
    ##  (Need a rejection method)
    ## http://eris.cobaltirc.org/dev/bugs/?task_id=32&project=1
  }

  ## FIXME methods to provide interface to pending_reg
  $self->_r_pending_reg->{ $conn->wheel_id }->{user}  = $username;
  $self->_r_pending_reg->{ $conn->wheel_id }->{gecos} = $gecos || '';
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
  ##   A "PASS" command is not required for either client or server
  ##   connection to be registered, but it must precede the server
  ##   message or the latter of the NICK/USER combination.
  ##
  ## Preserve PASS for later checking by register_user_local.

  my $pass = $ev->params->[0];
  $self->_r_pending_reg->{ $conn->wheel_id }->{pass} = $pass;
}

## FIXME call burst methods to sync up after registration?
##  or call() burst handlers via Protocol?

## FIXME an idle timer in Ping should issue a disconnect
##  if the user takes longer than max idle time to register
##  we need to be able to catch the disconnect and clear the pending_reg


1;
