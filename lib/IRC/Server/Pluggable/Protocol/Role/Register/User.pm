package IRC::Server::Pluggable::Protocol::Role::Register::User;

use 5.12.1;
use Carp;

use Moo::Role;
use strictures 1;

requires qw/
  config

  users
  peers
  _pending_reg

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

  ## FIXME
  ##  -> auth check:
  ##    - check pass if present
  ##  -> ban check:
  ##    -> process() pre-registration event
  ##  -> __register_user_create_obj()
  ##  -> dispatch 001 .. 004 numerics, lusers, motd, default mode
  ##  -> emit registered event
}

sub __register_user_ready {
  my ($self, $conn) = @_;

  ## Should be called if a local user may be ready to complete
  ## registration; in other words, NICK, USER, and identd/hostname
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
  ## next-hop peer
}

sub __register_user_create_obj {
  ## IRC::User Factory
  ## FIXME need to figure out sane usage for this
}


1;
