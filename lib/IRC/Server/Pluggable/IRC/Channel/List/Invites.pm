package IRC::Server::Pluggable::IRC::Channel::List::Invites;

use Carp;
use Moo;
use strictures 1;

extends 'IRC::Server::Pluggable::IRC::Channel::List';

around 'add' => sub {
  my ($self, $nickname, $source) = @_;

  confess "add() given insufficient arguments"
    unless defined $nickname and defined $source;

  ## $invite_list->get($nickname) = [ $src, $ts ]
  ## Higher-level has to handle case sensitivity issues.
  $self->orig( $nickname, [ $source, time() ] )
};

1;
