package IRC::Server::Pluggable::Protocol::Role::Basic::Peers;

use strictures 1;
use Moo::Role;

use POE;

use namespace::clean -except => 'meta';

sub cmd_from_peer_server {
  ## Peer introducing server.
  my ($self, $conn, $event) = @_;

  my $intro_by = $event->prefix;
  my ($new_peer_name, $hop_count, $gecos_str) = @{ $event->params };

  ## FIXME
  ##  ... ->can() hooks for leaf/hub verification etc?
  ##  Create a Peer obj for this w/ route() set to our intro_by route()
}


sub cmd_from_peer_squit {

}



1;
