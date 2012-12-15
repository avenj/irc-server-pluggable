package IRC::Server::Pluggable::Role::Metadata;

use Moo::Role;
use strictures 1;
use Carp 'confess';

use namespace::clean;

has '_metadata' => (
  lazy => 1,
  is   => 'ro',
  isa  => HashRef,
  writer    => '_set_metadata',
  predicate => '_has_metadata',
  clearer   => '_clear_metadata',
  default   => sub { {} },
);

sub add_meta {
  my ($self, $key, $val) = @_;
  confess "Expected a key and value"
    unless defined $key and defined $value;
  $self->_metadata->{$key} = $value
}

sub del_meta {
  my ($self, $key) = @_;
  confess "Expected a key" unless defined $key;
  delete $self->_metadata->{$key}
}

sub get_meta {
  my ($self, $key) = @_;
  $self->_metadata->{$key}
}

sub list_meta {
  my ($self) = @_;
  keys %{ $self->_metadata }
}

1;
