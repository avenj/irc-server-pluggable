package IRC::Server::Pluggable::IRCSock::Listener;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

has 'wheel' => (
  required => 1,
  
  isa => Str,
  
);

has 'addr'  => (

);

has 'port'  => (

);

has 'idle'  => (

);

has 'ssl'   => (

);

1;
