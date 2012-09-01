package IRC::Server::Pluggable::IRC::Channel::List::Bans;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable::Utils qw/normalize_mask/;

extends 'IRC::Server::Pluggable::IRC::Channel::List';


around 'add' => sub {
  my ($orig, $self, $mask, $array_params) = @_;

  my ($setter, $ts) = @{ $array_params // [] };

  confess "add() given insufficient arguments"
    unless defined $mask and defined $setter and defined $ts;

  ## Normalize and add mask.
  $self->$orig( normalize_mask($mask), [ $setter, $ts ] )
};

1;
