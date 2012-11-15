package IRC::Server::Pluggable::Protocol::Role::Version;

use 5.12.1;
use Carp;

use Moo::Role;
use strictures 1;


use namespace::clean -except => 'meta';


sub _r_proto_build_isupport {

}


sub cmd_from_client_version {
  my ($self, $conn, $event) = @_;

  ## FIXME may be for us (no params) or remote (params being server name/mask)

  if (@{ $event->params }) {
    ## FIXME have an arg, should be server name/mask
    ##  need IRC::Peers method to find by mask
    ##  relay to first or return unknown server rpl
    return
  }

  ## No params, send back our version & ISUPPORT
}


sub cmd_from_peer_version {
  ## FIXME get client and call back to cmd_from_client_version
  ##  (with server name/mask arg dropped)
}



1;
