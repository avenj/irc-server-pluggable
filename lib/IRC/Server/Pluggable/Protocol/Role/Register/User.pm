package IRC::Server::Pluggable::Protocol::Role::Register::User;

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
  _pending_reg

  numeric

  process
  emit
  emit_now
/;


sub register_user_local {
  my ($self, $conn) = @_;

  ## Has this Backend::Connect finished registration?
  my $pending_ref = $self->__register_user_ready($conn);
  return unless $pending_ref;

  delete $self->_pending_reg->{ $conn->wheel_id };

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

  $self->dispatcher->dispatch(
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

  $self->dispatcher->dispatch(
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

  my $pending_ref = $self->_pending_reg->{ $conn->wheel_id } || return;

  unless ( $conn->has_wheel ) {
    ## Connection's wheel has disappeared.
    delete $self->_pending_reg->{ $conn->wheel_id };
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

  ## FIXME remote User objs need a route() specifying wheel_id for
  ## next-hop peer; i.e., the peer that introduced the user to us
  ##  take next-hop Peer/conn obj as arg, pull wheel_id
}

sub __register_user_create_obj {
  my ($self, %params) = @_;

  ## Override me to change the class constructed for a User.

  IRC::Server::Pluggable::IRC::User->new(%params)
}


1;
