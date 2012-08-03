package IRC::Server::Pluggable::IRC::Channel;
## Base class for Channels.
## Overridable by Protocols.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable::Types;


has 'users' => (
  is  => 'ro',
  isa => HashRef,
  default => sub { {} },
);

has 'modes' => (
  is  => 'ro',
  isa => HashRef,
  default => sub { {} },
);

has 'array_bans' => (
  is  => 'ro',
  isa => ArrayRef,
  default => sub { [] },
);

1;
