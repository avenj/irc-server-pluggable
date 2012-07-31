package IRC::Server::Pluggable::IRCSock::Listener;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable::Types;

has 'wheel' => (
  required => 1,
  
  isa => Wheel,
  is  => 'ro',

  clearer => 'clear_wheel',
  writer  => 'set_wheel',  
);

has 'addr'  => (
  required => 1,
  
  isa => Str,
  is  => 'ro',
  
  writer    => 'set_addr',
);

has 'port'  => (
  required => 1,
  
  isa => Int,
  is  => 'ro',
  
  writer    => 'set_port',
);

has 'idle'  => (
  ## FIXME
);

has 'ssl'   => (
  isa => Bool,
  is  => 'ro',
  
  predicate => 'has_ssl',
  writer    => 'set_ssl',
  
  default => sub { 0 },
);

1;
