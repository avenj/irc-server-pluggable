package IRC::Server::Pluggable::IRC::Peers;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable::Types;

use IRC::Server::Tree::Network;

use namespace::clean -except => 'meta';

has '_peers' => (
  lazy    => 1,
  is      => 'ro',
  isa     => HashRef,
  writer  => '_set_peers',
  default => sub { {} },
);

## FIXME
## When adding or removing peers, they should be added/removed
## from the _map
## Per the RFC, we can only realistically map peers matching route_ids
## to the set of peers beneath them.
has '_map' => (
  lazy    => 1,
  is      => 'ro',
  writer  => '_set_map',
  builder => '_build_map',
  isa     => sub {
    is_Object($_[0])
      and $_[0]->isa('IRC::Server::Tree::Network')
      or confess "$_[0] is not a IRC::Server::Tree::Network"
  },
);

sub _build_map {
  my ($self) = @_;
  IRC::Server::Tree::Network->new
}

sub add {
  my ($self, $peer) = @_;

  confess "$peer is not a IRC::Server::Pluggable::IRC::Peer"
    unless is_Object($peer)
    and $peer->isa('IRC::Server::Pluggable::IRC::Peer');

  my $s_name = lc( $peer->name );

  $self->_peers->{$s_name} = $peer;

  $peer
}

sub as_array {
  my ($self) = @_;

  [ map { $self->_peers->{$_}->name } keys %{ $self->_peers } ]
}

sub by_name {
  my ($self, $s_name) = @_;

  confess "by_name() called with no server specified"
    unless defined $s_name;

  $self->_peers->{ lc($s_name) }
}

sub del {
  my ($self, $s_name) = @_;

  confess "del() called with no peer specified"
    unless defined $s_name;

  delete $self->_peers->{ lc($s_name) }
}


1;
