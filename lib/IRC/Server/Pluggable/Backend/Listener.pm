package IRC::Server::Pluggable::Backend::Listener;

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
  
  writer => 'set_addr',
);

has 'port'  => (
  required => 1,
  
  isa => Int,
  is  => 'ro',
  
  writer => 'set_port',
);

has 'idle'  => (
  lazy => 1,

  isa => Num,
  is  => 'rw',
  
  ## FIXME?

  predicate => 'has_idle',
  writer    => 'set_idle',
  
  default => sub { 0 },
);

has 'ssl'   => (
  isa => Bool,
  is  => 'ro',
  
  predicate => 'has_ssl',
  writer    => 'set_ssl',
  
  default => sub { 0 },
);

1;
