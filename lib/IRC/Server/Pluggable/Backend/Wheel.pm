package IRC::Server::Pluggable::Backend::Wheel;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable::Types;

has 'is_disconnecting' => (
  is  => 'rw',
  default => sub { 0 },
);

has 'is_pending_compress' => (
  isa => Bool,
  is  => 'rw',
  default => sub { 0 },
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

has 'protocol' => (
  required => 1,
  
  isa => InetProtocol,
  is  => 'ro',
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

has 'wheel' => (
  required => 1,

  isa => Wheel,
  is  => 'ro',
  
  clearer => 'clear_wheel',
  writer  => 'set_wheel',
);

1;
