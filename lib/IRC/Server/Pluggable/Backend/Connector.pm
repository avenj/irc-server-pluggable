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
  lazy => 1,

  isa => Str,
  is  => 'ro',
  
  predicate => 'has_bindaddr',
  writer    => 'set_bindaddr',
  
  default => sub { '' },
);

has 'args' => (
  lazy => 1,

  isa => Defined,
  is  => 'ro',
  
  writer => 'set_args',
  
  default => sub { {} },
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
  
  default => sub { 0 },
);

has 'wheel' => (
  required => 1,
  
  isa => Wheel,
  is  => 'ro',
  
  clearer => 'clear_wheel',
  writer  => 'set_wheel',
);

1;
