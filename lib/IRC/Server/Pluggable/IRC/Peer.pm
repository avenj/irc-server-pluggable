package IRC::Server::Pluggable::IRC::Peer;
## Base class for Peers.
## Overridable by Protocols.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;


has 'name' => (
  required => 1,
  is  => 'ro',
  isa => Str,
  writer => 'set_name',
);

has 'route' => (
  ## List of hops to peer.
  required => 1,
  is  => 'ro',
  isa => ArrayRef,
  writer => 'set_route',
);


1;
