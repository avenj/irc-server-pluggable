package IRC::Server::Pluggable::IRC::Tree;

## Array-type object representing a network map.
## Root node is 'SELF'
##      'hub1' => [
##          'leafA' => [],
##          'leafB' => [],
##       ],
##       'hub2' => [
##              'leafA' => [],
##              'leafB' => [],
##       ],

use strictures 1;
use Carp;

sub new {
  my $class = shift;

  my $self = ref $_[0] eq 'ARRAY' ? $_[0] : [ @_ ] ;

  bless $self, $class;

  $self
}


## Fundamentals:
sub add_node_to_parent_ref {
  ## add_node_to_parent( $parent_ref, $name )
  ## add_node_to_parent( $parent_ref, $name, $arrayref )
  my ($self, $parent_ref, $name, $arrayref) = @_;

  push @$parent_ref, $name, ($arrayref||[])
}

sub add_node_to_parent {
  my ($self, $parent_name, $name, $arrayref) = @_;
  ## FIXME find ref for parent name via path_to_server_array
  ## add_node_to_parent_ref() for the ref
}

sub del_node_by_name {
  ## FIXME
  ## Find and splice out a node by name.
}

## Higher-level:
sub path_to_server {
  ## FIXME call to path_to_server_array instead
  ##  then return a list of just the names in the path
  my ($self, $server_name, $parent_ref) = @_;

  my @queue = ( PARENT => ($parent_ref || $self) );
  my %route;

  ## Breadth-first search.
  while (my ($parent_name, $parent_ref) = splice @queue, 0, 2) {
    ## Iterarate child nodes to find a route.
    ## The @queue is paths we haven't checked yet.

    return [ ] if $parent_name eq $server_name;

    my @leaf_list = @$parent_ref;

    while (my ($child_name, $child_ref) = splice @leaf_list, 0, 2) {
      ## If we don't have a route for the name of this node,
      ## set one up.
      unless ( $route{$child_name} ) {
        ## If our parent has a route, prepend it.
        $route{$child_name} =
          [ @{ $route{$parent_name}||[] }, $child_name ];

        ## If the child we're checking now is the one we're looking for,
        ## return an arrayref of names.
        return \@{$route{$child_name}} if $child_name eq $server_name;

        ## If we didn't hit on our target node yet, queue the child to
        ## search.
        push @queue, $child_name, $child_ref if @$child_ref;
      }
    }

  }

  return
}

sub path_to_server_indexes {
  ## Like above, but return indexes into arrays describing the path
  my ($self, $server_name, $parent_ref) = @_;

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

sub child_node_for {
  my ($self, $server_name, $parent_ref) = @_;
  $parent_ref = $self unless defined $parent_ref;


}

sub add_server_to_hub {

}

sub del_server_from_hub {

}

1;
