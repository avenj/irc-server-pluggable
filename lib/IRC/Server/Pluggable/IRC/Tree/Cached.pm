package IRC::Server::Pluggable::IRC::Tree::Cached;

use strictures 1;

use overload
  bool     => sub { 1 },
  '@{}'    => 'tree_array',
  fallback => 1;

our @ISA = 'IRC::Server::Pluggable::IRC::Tree';

sub new {
  my $class = shift;
  my $self  = {};
  bless $self, $class;

  $self->{treeArray} = ref $_[0] eq 'ARRAY' ? $_[0] : [ @_ ]
  $self->{routed}    = {};

  $self
}

sub tree_array {
  my ($self) = @_;
  $self->{treeArray}
}

sub trace_indexes {
  my $self = shift;

  if (@_ > 1) {
    ## Have a starting ref specified.
    ## Don't cache.
    return $self->SUPER::trace_indexes(@_)
  }

  my $name = $_[0];

  if ( $self->{routed}->{$name} ) {
    return $self->{routed}->{$name}
  } else {
    my $returned = $self->SUPER::trace_indexes(@_);
    $self->{routed}->{$name} = $returned;
    return $returned
  }
}

sub del_node_by_name {
  my $self = shift;
  my $name = $_[0];

  delete $self->{routed}->{$name};

  my $deleted;
  if ( $deleted = $self->SUPER::del_node_by_name(@_) ) {
    for my $name ( @{ $self->SUPER::names_beneath($deleted) } ) {
      delete $self->{routed}->{$name}
    }
  }

  return $deleted
}
