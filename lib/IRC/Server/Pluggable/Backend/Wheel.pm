package IRC::Server::Pluggable::Backend::Wheel;

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

has 'peeraddr' => (
  required => 1,
  
  isa => Str,
  is  => 'ro',
  
  writer => 'set_peeraddr',
);

has 'peerport' => (
  required => 1,
  
  isa => Int,
  is  => 'ro',
  
  writer => 'set_peerport',
);

has 'sockaddr' => (
  required => 1,
  
  isa => Str,
  is  => 'ro',
  
  writer => 'set_sockaddr',
);

has 'sockport' => (
  required => 1,
  
  isa => Int,
  is  => 'ro',
  
  writer => 'set_sockport',
);

1;
