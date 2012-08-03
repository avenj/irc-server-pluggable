package IRC::Server::Pluggable::Protocol::TS6::Peer;
## ISA IRC::Server::Pluggable::IRC::Peer

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

extends 'IRC::Server::Pluggable::IRC::Peer';

has 'sid' => (
  ## FIXME
  ##  See notes regarding TS5 compat in User.pm
);

1;
