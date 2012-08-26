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

  my $peer = $self->peers->by_name($s_name) || return;

  if ( $peer->has_conn ) {
    ## Locally connected peer.
    return $peer->conn->has_wheel ? $peer->conn->wheel_id : ()
  }

  ## Remote user; retrieve path (local peer).
  my $local_peer = $self->peers->by_name( $peer->route ) || return;

  $local_peer->has_conn ? $local_peer->conn->wheel_id : ()
}

sub route_to_user {
  my ($self, $nick) = @_;

  my $user = $self->users->by_name($nick) || return;

  if ( $user->has_conn ) {
    return $user->conn->has_wheel ? $user->conn->wheel_id : ()
  }

  ## Remote user; retrieve path, similar to above.
  my $peer = $self->peers->by_name( $user->route ) || return;

  $peer->has_conn ? $peer->conn->wheel_id : ()
}

sub route_to_user_is_local {
  my ($self, $nick) = @_;

  my $user = $self->users->by_name($nick) || return;

  $user->has_conn ? $user : ()
}

1;
