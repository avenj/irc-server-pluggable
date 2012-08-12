package IRC::Server::Pluggable::IRC::Channel::List;

## Base class for lists for a channel (f.ex banlists)

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable qw/
  Types
  Utils
/;

has '_list' => (
  lazy => 1,
  is  => 'ro',
  isa => HashRef,
  default => sub { {} },
);

sub add {
  my ($self, $item, $value) = @_;
  
  $self->_list->{$item} = $value;
}

sub del {
  my ($self, $item) = @_;

  delete $self->_list->{$item}
}

sub get {
  my ($self, $item) = @_;

  $self->_list->{$item}
}

sub keys {
  my ($self) = @_;
  
  wantarray ? (keys %{ $self->_list }) : [ keys %{ $self->_list } ]
}

1;
