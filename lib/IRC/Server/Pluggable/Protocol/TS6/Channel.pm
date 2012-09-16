package IRC::Server::Pluggable::Protocol::TS6::Channel;
## ISA IRC::Server::Pluggable::IRC::Channel

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable qw/
  Types
/;

use namespace::clean -except => 'meta';

extends 'IRC::Server::Pluggable::IRC::Channel';

has 'ts' => (
  required => 1,
  is  => 'ro',
  isa => Num,
  writer => 'set_ts',
);

1;
