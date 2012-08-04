package IRC::Server::Pluggable::IRC::User;
## Base class for Users.
## Overridable by Protocols.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;


has 'nick' => (
  required => 1,
  is  => 'ro',
  isa => Str,
  writer => 'set_nick',
);

has 'user' => (
  required => 1,
  is  => 'ro',
  isa => Str,
  writer => 'set_user',
);

has 'host' => (
  required => 1,
  is  => 'ro',
  isa => Str,
  writer => 'set_host',
);

has 'server' => (
  required => 1,
  is  => 'ro',
  isa => Str,
  writer => 'set_server',
);

has 'realname' => (
  required => 1,
  is  => 'ro',
  isa => Str,
  writer => 'set_realname',
);

has 'modes' => (
  lazy => 1,
  is  => 'ro',
  isa => ArrayRef,
  default => sub { [] },
);


q{
  <Schroedingers_hat> i suppose I could analyse the gif and do a fourier 
   decomposition, then feed that into a linear model and see what 
   happens...
  <Schroedingers_hat> ^ The best part is that sentence was 
   about breasts.
};
