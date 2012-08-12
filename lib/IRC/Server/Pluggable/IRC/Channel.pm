package IRC::Server::Pluggable::IRC::Channel;
## Base class for Channels.
## Overridable by Protocols.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable qw/
  Types
  Utils
/;


has 'name' => (
  required => 1,

  is  => 'ro',
  isa => Str,
);

has 'users' => (
  lazy => 1,

  is  => 'ro',
  isa => HashRef,

  default => sub { {} },
  writer  => 'set_users',
);

## FIXME track status modes separately, perhaps as part of ->users ?
##  Relying on ->prefix_map() and ->valid_channel_modes() from Protocol 
##  to find out what modes actually are/do, so this all has to be handled 
##  outside of these per-channel objects ...

has 'modes' => (
  lazy => 1,

  is  => 'ro',
  isa => HashRef,

  default => sub { {} },
  writer  => 'set_modes',
);

has 'array_bans' => (
  lazy => 1,

  is  => 'ro',
  isa => ArrayRef,

  default => sub { [] },
  writer  => 'set_array_bans',
);


q{
 <LeoNerd> Hehe.. this does not bode well. I google searched for "MSWin32 
  socket non blocking connect", to read about how to do it. Got 1 404, 1 
  ancient article about 1990s UNIX, one about python, then the 4th 
  result is me, talking about how I don't know how to do it.
};
