package IRC::Server::Pluggable::IRC::Channel::List::Bans;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable qw/
  Types
  Utils
/;


extends 'IRC::Server::Pluggable::IRC::Channel::List';


around 'add' => sub {
  my ($orig, $self, $mask, $setter, $ts) = @_;

  confess "add() given insufficient arguments"
    unless $mask && $setter && defined $ts;

  $self->$orig( $mask, [ $setter, $ts] )
};


## ... it would be nice to provide mask-matching here, but then
##  we need to propogate casemaps over this way ...


1;
