package IRC::Server::Pluggable::Protocol::Role::Routing;

use 5.12.1;
use strictures 1;

use Carp;
use Moo::Role;

requires qw/
  channels
  peers
  users
/;

sub route_to_peer {
  my ($self, $s_name) = @_;

  my $peer = $self->route_to_peer_is_active($s_name) || return;

  $peer->conn->wheel_id
}

sub route_to_peer_is_active {
  my ($self, $s_name) = @_;

  my $peer = $self->peers->by_name($s_name) || return;

  return unless $peer->has_conn;
  return unless $peer->conn->has_wheel;

  $peer
}

sub route_to_user {
  my ($self, $nick) = @_;

  my $user = $self->users->by_name($nick) || return;

  ## Local user:
  return $user->conn->wheel_id if $user->has_conn;

  ## Remote user:
  my $peer = $self->peers->by_name( $user->server ) || return;

  $peer->has_conn ? $peer->conn->wheel_id : ()
}

sub route_to_user_is_local {
  my ($self, $nick) = @_;

  my $user = $self->users->by_name($nick) || return;

  $user->has_conn ? $user : ()
}

sub route_to_user_is_active {
  my ($self, $nick) = @_;

  my $user = $self->users->by_name($nick) || return;

  ## Local user:
  if ( $self->route_to_user_is_local($nick) ) {
    return $user if $user->has_conn and $user->conn->has_wheel
    return
  }

  ## Remote user:
  my $s_name = $user->server;
  return $user if $self->route_to_peer_is_active($s_name);

  $user
}

1;
