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



q{
 <LeoNerd> Hehe.. this does not bode well. I google searched for "MSWin32 
  socket non blocking connect", to read about how to do it. Got 1 404, 1 
  ancient article about 1990s UNIX, one about python, then the 4th 
  result is me, talking about how I don't know how to do it.
};
