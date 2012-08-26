package IRC::Server::Pluggable::Protocol::Role::Routing;

use 5.12.1;
use strictures 1;

use Carp;
use Moo::Role;

requires qw/
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

sub route_to_peer_is_local {
  my ($self, $s_name) = @_;

  my $peer = $self->peers->by_name($s_name) || return;

  $peer->has_conn ? $peer : ()
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

=pod

=head1 NAME

IRC::Server::Pluggable::Protocol::Role::Routing

=head1 SYNOPSIS

  ## In a Protocol subclass:
  with 'IRC::Server::Pluggable::Protocol::Role::Routing';
  my $target_id = $self->route_to_user( $nickname );
  my $target_id = $self->route_to_peer( $server_name );

  if ( $self->route_to_user_is_local( $nickname ) ) {
   . . .
  }
  if ( $self->route_to_peer_is_local( $server_name ) ) {
   . . .
  }

=head1 DESCRIPTION

A L<Moo::Role> providing route-retrieval methods operating on the 
consumer's B<users> and B<peers> attributes (which should be 
L<IRC::Server::Pluggable::IRC::Users> and 
L<IRC::Server::Pluggable::IRC::Peers> instances, respectively).

=head2 Routing fundamentals

=over

=item *

Routes are acyclic; a message to a single user travels in one direction, 
possibly across multiple servers but using the shortest possible path.

=item *

A message to multiple targets is dispatched individually in one direction 
to each target.

=item *

A message to a channel is relayed to any local users present on the 
channel. Messages are relayed to any peers responsible for 
introducing users present on the channel; the receiving peer 
dispatches to its local clients and to its own peers as-needed until the 
message has been propogated to all clients present.

=back

=head2 Peers

B<route_to_peer> checks if the peer is local to our server; if so, the 
specified peer's wheel ID is returned.

If the peer is remote to us, the local Peer that introduced the server is 
retrieved; the local Peer's wheel ID is returned.

=head2 Users

B<route_to_user> checks if the user belongs to our server; if so, the 
local user's wheel ID is returned.

If the user is remote to us, the local Peer that introduced the user is 
retrieved; the local Peer's wheel ID is returned.

Returns empty list if the route could not be resolved.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
