package IRC::Server::Pluggable::Role::Peers;

use strictures 1;
use Moo::Role;

use POE;

use namespace::clean -except => 'meta';

sub ROLES () {
  'IRC::Server::Pluggable::Protocol::Role::Peers::'
}


sub cmd_from_peer_server {}
sub cmd_from_peer_squit  {}



1;
