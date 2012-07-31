package IRC::Server::Pluggable::Backend::Event;

## Base class for incoming/outgoing events to<->from Backend.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

has 'prefix' => (
  required => 1,
  is => 'ro',
);

has 'command' => (
  required => 1,
  is => 'ro',
);

has 'params' => (
  required => 1,
  is => 'ro',
);

has 'raw_line' => (
  required => 1,
  is => 'ro',
);

1;
