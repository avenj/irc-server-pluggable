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


q{
 <rac> "This option should never be turned on by any -O option since it 
  can result in incorrect output for programs which depend on an exact 
  implementation of IEEE or ISO rules/specifications for math functions. 
 <rac> i've said it before, and i'll say it again ... i see no use in a 
  computer giving me the wrong answer very rapidly, i can do that myself
};
