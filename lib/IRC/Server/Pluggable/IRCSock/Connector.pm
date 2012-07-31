package IRC::Server::Pluggable::IRCSock::Connector;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable::Types;

has 'wheel' => (
  required => 1,
  
  isa => Wheel,
  is  => 'ro',
  
  predicate => 'has_wheel',
  writer    => 'set_wheel',
  clearer   => 'clear_wheel',
);

has 'addr' => (
  required => 1,
  
  isa => Str,
  is  => 'ro',
  
  predicate => 'has_addr',
  writer    => 'set_addr',
);

has 'port' => (
  required => 1,
  
  isa => Int,
  is  => 'ro',
  
  predicate => 'has_port',
  writer    => 'set_port',
);

has 'bindaddr' => (
  isa => Str,
  is  => 'ro',
  
  predicate => 'has_bindaddr',
  writer    => 'set_bindaddr',
);

has 'ssl' => (
  isa => Bool,
  is  => 'ro',
  
  predicate => 'has_ssl',
  writer    => 'set_ssl',
);

1;
