package IRC::Server::Pluggable::IRC::Tree;

## Array-type object representing a network map.

use strictures 1;
use Carp;

sub new {
  my $class = shift;

  my $self = ref $_[0] eq 'ARRAY' ? $_[0] : [ @_ ] ;

  bless $self, $class;

  $self
}

sub path_to_server_indexes {
  my ($self, $server_name, $parent_ref) = @_;

  ## Return indexes into arrays describing the path
  ## Return value is the full list of indexes to get to the array
  ## belonging to the named server
  ##  i.e.:
  ##   1, 3, 1
  ##   $parent_ref->[1] is a ref belonging to an intermediate hop
  ##   $parent_ref->[1]->[3] is a ref belonging to an intermediate hop
  ##   $parent_ref->[1]->[3]->[1] is the ref belonging to the target hop
  ## Subtracting one from an index will get you the NAME value.

  my @queue = ( PARENT => ($parent_ref || $self) );
  my %route;

  ## Breadth-first search.
  my $parent_idx = 0;
  PARENT: while (my ($parent_name, $parent_ref) = splice @queue, 0, 2) {
    ## Iterarate child nodes to find a route.
    ## The @queue is paths we haven't checked yet.

    return [ $parent_idx+1 ] if $parent_name eq $server_name;

    my @leaf_list = @$parent_ref;
    my $child_idx = 0;
    CHILD: while (my ($child_name, $child_ref) = splice @leaf_list, 0, 2) {
      unless ( $route{$child_name} ) {
        $route{$child_name} =
          [ @{ $route{$parent_name}||[] }, $child_idx+1 ];

        return \@{$route{$child_name}} if $child_name eq $server_name;

        push @queue, $child_name, $child_ref;
      }

      $child_idx += 2;
    }  ## CHILD

    $parent_idx += 2;
  }  ## PARENT

  return
}

sub path_to_server {
  my ($self, $server_name, $parent_ref) = @_;

  $parent_ref = $self unless defined $parent_ref;

  my $index_route =
    $self->path_to_server_indexes($server_name, $parent_ref)
    or return;

  ## Build a list of names for each member of the path
  my ($cur_ref, @names) = $parent_ref;
  while (my $idx = shift @$index_route) {
    push(@names, $cur_ref->{ $idx - 1 });
    $cur_ref = $cur_ref->{$idx};
  }

  \@names
}

sub child_node_for {
  my ($self, $server_name, $parent_ref) = @_;

  $parent_ref = $self unless defined $parent_ref;

  my $index_route =
    $self->path_to_server_indexes($server_name, $parent_ref)
    or return;

  ## Recurse the list indexes.
  my $cur_ref = $parent_ref;

  while (my $idx = shift @$index_route) {
    $cur_ref = $cur_ref->[$idx]
  }

  $cur_ref
}

sub add_node_to_parent_ref {
  ## add_node_to_parent( $parent_ref, $name )
  ## add_node_to_parent( $parent_ref, $name, $arrayref )
  my ($self, $parent_ref, $name, $arrayref) = @_;

  push @$parent_ref, $name, ($arrayref||[])
}

sub add_node_to_top {
  my ($self, $name, $arrayref) = @_;

  $self->add_node_to_parent_ref( $self, $name, $arrayref )
}

sub add_node_to_name {
  my ($self, $parent_name, $name, $arrayref) = @_;

  ## Can be passed $self like add_node_to_parent_ref
  ## Should just use add_node_to_top instead, though
  if ($parent_name eq $self) {
    return $self->add_node_to_top($name, $arrayref)
  }

  my $index_route =
    $self->path_to_server_indexes($parent_name)
    or carp "Cannot add node to nonexistant parent $parent_name"
    and return;

  my $cur_ref = $self;

  while (my $idx = shift @$index_route) {
    $cur_ref = $cur_ref->[$idx]
  }

  ## Now in the ref belonging to our named parent.
  $self->add_node_to_parent_ref($cur_ref, $name, $arrayref || [] )
}

sub del_node_by_name {
  my ($self, $name) = @_;

  ## Returns deleted node.

  my $index_route =
    $self->path_to_server_indexes($name)
    or carp "Cannot del nonexistant node $name"
    and return;

  my $idx_for_ref  = pop @$index_route;
  my $idx_for_name = $idx_for_ref - 1;

  my $cur_ref = $self;
  while (my $idx = @$index_route) {
    $cur_ref = $cur_ref->[$idx]
  }

  ## Should now be in top-level container and have index values
  ## for the name/ref that we're deleting.
  my ($del_name, $del_ref) = splice @$cur_ref, $idx_for_name, 2;

  $del_ref
}


1;
