package IRC::Server::Pluggable::IRC::Channel::List::Bans;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable::Utils qw/normalize_mask/;

extends 'IRC::Server::Pluggable::IRC::Channel::List';


around 'add' => sub {
  my ($orig, $self, $mask, $setter, $ts) = @_;

  confess "add() given insufficient arguments"
    unless $mask and defined $setter and defined $ts;

  ## Normalize and add mask.
  $self->$orig( normalize_mask($mask), [ $setter, $ts ] )
};

1;
