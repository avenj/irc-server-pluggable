package IRC::Server::Pluggable::Backend::Connector;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable::Types;

has 'addr' => (
  required => 1,
  
  isa => Str,
  is  => 'ro',
  
  writer => 'set_addr',
);

has 'bindaddr' => (
  isa => Str,
  is  => 'ro',
  
  predicate => 'has_bindaddr',
  writer    => 'set_bindaddr',
);

has 'port' => (
  required => 1,
  
  isa => Int,
  is  => 'ro',

  writer => 'set_port',
);

has 'protocol' => (
  required => 1,

  isa => InetProtocol,
  is  => 'ro',
);

has 'ssl' => (
  isa => Bool,
  is  => 'ro',
  
  predicate => 'has_ssl',
  writer    => 'set_ssl',
);

has 'wheel' => (
  required => 1,
  
  isa => Wheel,
  is  => 'ro',
  
  clearer => 'clear_wheel',
  writer  => 'set_wheel',
);

1;
