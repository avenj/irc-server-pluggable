package IRC::Server::Pluggable::IRC::Peers;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable::Types;

use IRC::Server::Tree::Network;

use Scalar::Util 'weaken';

use namespace::clean -except => 'meta';


has '_peers' => (
  lazy    => 1,
  is      => 'ro',
  isa     => HashRef,
  writer  => '_set_peers',
  default => sub { {} },
);

has '_by_id' => (
  lazy    => 1,
  is      => 'ro',
  isa     => HashRef,
  default => sub { {} },
);

sub add {
  my ($self, $peer) = @_;

  confess "$peer is not a IRC::Server::Pluggable::IRC::Peer"
    unless is_Object($peer)
    and $peer->isa('IRC::Server::Pluggable::IRC::Peer');

  my $s_name = lc( $peer->name );

  $self->_peers->{$s_name} = $peer;

  if ($peer->has_conn) {
    $self->_by_id->{ $peer->route() } = $peer;
    weaken($self->_by_id->{ $peer->route() });
  }

  $peer
}

sub as_array {
  my ($self) = @_;

  [ map { $self->_peers->{$_}->name } keys %{ $self->_peers } ]
}

sub by_id {
  my ($self, $id) = @_;

  confess "by_id() called with no ID specified"
    unless defined $id;

  $self->_by_id->{$id}
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
