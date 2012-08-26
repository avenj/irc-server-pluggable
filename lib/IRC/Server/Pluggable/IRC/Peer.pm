package IRC::Server::Pluggable::IRC::Peer;
## Base class for Peers.
## Overridable by Protocols.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable qw/
  Types
/;

has 'conn' => (
  ## Our directly-linked peers should have a Backend::Wheel
  lazy => 1,

  is   => 'ro',
  isa  => sub {
    is_Object($_[0])
      and $_[0]->isa('IRC::Server::Pluggable::Backend::Wheel')
      or confess "$_[0] is not a IRC::Server::Pluggable::Backend::Wheel"
  },

  predicate => 'has_conn',
  writer    => 'set_conn',
  clearer   => 'clear_conn',
);

has 'name' => (
  required => 1,
  is     => 'ro',
  isa    => Str,
  writer => 'set_name',
);

1;
