package IRC::Server::Pluggable::IRC::Tree;

## Array-type object representing a network map.
## Uses breadth-first recursion to find a path to a node.
## Uses depth-first recursion to build hashes or printable maps.

use strictures 1;
use Carp;

sub new {
  my $class = shift;
  my $self = ref $_[0] eq 'ARRAY' ? $_[0] : [ @_ ] ;
  bless $self, $class
}

sub add_node_to_parent_ref {
  my ($self, $parent_ref, $name, $arrayref) = @_;

  push @$parent_ref, $name, ($arrayref||=[]);

  $arrayref
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
    $self->trace_indexes($parent_name)
    or carp "Cannot add node to nonexistant parent $parent_name"
    and return;

  my $cur_ref = $self;

  while (my $idx = shift @$index_route) {
    $cur_ref = $cur_ref->[$idx]
  }

  ## Now in the ref belonging to our named parent.
  $self->add_node_to_parent_ref($cur_ref, $name, $arrayref || [] )
}

sub __t_add_to_hash {
  my ($parent_hash, $name, $node_ref) = @_;

  $parent_hash->{$name} = {}
    unless exists $parent_hash->{$name};

  my @list = @$node_ref;

  while (my ($nextname, $nextref) = splice @list, 0, 2 ) {
    __t_add_to_hash( $parent_hash->{$name}, $nextname, $nextref )
  }
}

sub as_hash {
  my ($self, $parent_ref) = @_;

  $parent_ref = $self unless defined $parent_ref;

  my $mapref = {};

  my @list = @$parent_ref;

  while (my ($name, $node_ref) = splice @list, 0, 2 ) {
    __t_add_to_hash( $mapref, $name, $node_ref )
  }

  $mapref
}

sub as_list {
  my ($self, $parent_ref) = @_;
  @{ ref $parent_ref eq 'ARRAY' || $self }
}

sub child_node_for {
  my ($self, $server_name, $parent_ref) = @_;

  $parent_ref = $self unless defined $parent_ref;

  my $index_route =
    $self->trace_indexes($server_name, $parent_ref)
    or return;

  ## Recurse the list indexes.
  my $cur_ref = $parent_ref;

  while (my $idx = shift @$index_route) {
    $cur_ref = $cur_ref->[$idx]
  }

  $cur_ref
}

sub del_node_by_name {
  my ($self, $name, $parent_ref) = @_;

  ## Returns deleted node.

  my $index_route =
    $self->trace_indexes($name, $parent_ref)
    or carp "Cannot del nonexistant node $name"
    and return;

  my $idx_for_ref  = pop @$index_route;
  my $idx_for_name = $idx_for_ref - 1;

  my $cur_ref = $parent_ref || $self;
  while (my $idx = shift @$index_route) {
    $cur_ref = $cur_ref->[$idx]
  }

  ## Should now be in top-level container and have index values
  ## for the name/ref that we're deleting.
  my ($del_name, $del_ref) = splice @$cur_ref, $idx_for_name, 2;

  $del_ref
}

sub names_beneath {
  my ($self, $ref_or_name) = @_;

  ## Given either a ref (such as from del_node_by_name)
  ## or a name (ref is retrived), get the names of
  ## all the nodes in the tree under us.

  my $ref;
  if (ref $ref_or_name eq 'ARRAY') {
    $ref = $ref_or_name
  } else {
    $ref = $self->child_node_for($ref_or_name)
  }

  return unless $ref;

  my @list = @$ref;
  my @names;

  ## Recurse and accumulate names.
  while (my ($node_name, $node_ref) = splice @list, 0, 2) {
    push(@names, $node_name);
    push(@names, @{ $self->names_beneath($node_ref) || [] });
  }

  \@names
}

sub trace_names {
  my ($self, $server_name, $parent_ref) = @_;

  ## A list of named hops to the target.
  ## The last hop is the target's name.

  $parent_ref = $self unless defined $parent_ref;

  my $index_route =
    $self->trace_indexes($server_name, $parent_ref)
    or return;

  my ($cur_ref, @names) = $parent_ref;
  while (my $idx = shift @$index_route) {
    push(@names, $cur_ref->[ $idx - 1 ]);
    $cur_ref = $cur_ref->[$idx];
  }

  \@names
}

sub trace_indexes {
  my ($self, $server_name, $parent_ref) = @_;

  ## Defaults to operating on $self
  ## Return indexes into arrays describing the path
  ## Return value is the full list of indexes to get to the array
  ## belonging to the named server
  ##  i.e.:
  ##   1, 3, 1
  ##   $parent_ref->[1] is a ref belonging to an intermediate hop
  ##   $parent_ref->[1]->[3] is a ref belonging to an intermediate hop
  ##   $parent_ref->[1]->[3]->[1] is the ref belonging to the target hop
  ## Subtracting one from an index will get you the NAME value.

  ## A start-point.
  my @queue = ( PARENT => ($parent_ref || $self) );

  ## Our seen routes.
  my %route;

  my $parent_idx = 0;
  PARENT: while (my ($parent_name, $parent_ref) = splice @queue, 0, 2) {

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

sub print_map {
  my ($self, $parent_ref) = @_;

  $parent_ref = $self unless defined $parent_ref;

  my $indent = 1;

  my $recurse_print;
  $recurse_print = sub {
    my ($name, $ref) = @_;
    my @nodes = @$ref;

    if ($indent == 1 || scalar @nodes) {
      $name = "* $name";
    } else {
      $name = "` $name";
    }

    print( (' ' x $indent) . "$name\n" );

    while (my ($next_name, $next_ref) = splice @nodes, 0, 2) {
      $indent += 3;
      $recurse_print->($next_name, $next_ref);
      $indent -= 3;
    }
  };

  my @list = @$parent_ref;
  warn "No refs found\n" unless @list;
  while (my ($parent_name, $parent_ref) = splice @list, 0, 2) {
    $recurse_print->($parent_name, $parent_ref);
    $indent = 1;
  }

  return
}

1;

=pod

=head1 NAME

IRC::Server::Pluggable::IRC::Tree - Represent an IRC network tree

=head1 SYNOPSIS

  ## Basic path-tracing usage:
  my $tree = IRC::Server::Pluggable::IRC::Tree->new;

  $tree->add_node_to_top($_) for qw/ peerA peerB /;

  $tree->add_node_to_name('peerA', 'leafA');
  $tree->add_node_to_name('peerA', 'leafB');

  $tree->add_node_to_name('peerB', 'hubA');
  $tree->add_node_to_name('hubA', 'peerB');

  ## ARRAY of hop names between root and peerB:
  my $hop_names = $tree->trace_names( 'peerB' );

See the DESCRIPTION for a complete method list.

Also see C<eg/irc_tree.pl> in the distribution for a silly little 
interactive network simulator of sorts.

=head1 DESCRIPTION

An IRC network is defined as a 'spanning tree.'

An IRC network tree is essentially unordered; any node can have any 
number of child nodes, with the only rules being that:

=over

=item *

The tree remains a tree (it is acyclic; there is only one route between 
any two nodes, and no node has more than one parent)

=item *

No two nodes can share the same name.

=back

Currently, this module doesn't enforce the listed rules for performance 
reasons, but things will break if you add non-uniquely-named nodes. Be 
warned. (This behavior may change, at least via constructor flag.)

The object instance is a simple ARRAY and a new Tree can be created from 
an existing Tree:

  my $new_tree = IRC::Server::Pluggable::IRC::Tree->new( $old_tree );

Each individual node is also an array.

The general structure of the tree is a simple array-of-array:

  $self => [
    hubA => [
      leafA => [],
      leafB => [],
    ],

    hubB => [
      leafC => [],
      leafD => [],
    ],
  ],

The methods provided below can be used to manipulate the tree and 
determine hops in a path to an arbitrary node using a breadth-first 
search.

Currently routes are not memoized; that's left to a higher layer or 
subclass. Behavior subject to change.

=head2 new

Create a new network tree:

  my $tree = IRC::Server::Pluggable::IRC::Tree->new;

Optionally create a tree from an existing array, if you know what you're 
doing:

  my $tree = IRC::Server::Pluggable::IRC::Tree->new(
    [
      hubA => [
        leaf1 => [],
        leaf2 => [],
      ],
    ],
  );

=head2 add_node_to_parent_ref

  ## Add empty node to parent ref:
  $tree->add_node_to_parent_ref( $parent_ref, $new_name );
  ## Add existing node to parent ref:
  $tree->add_node_to_parent_ref( $parent_ref, $new_name, $new_ref );

Adds an empty or preexisting node to a specified parent reference.

Also see L</add_node_to_top>, L</add_node_to_name>

=head2 add_node_to_top

  $tree->add_node_to_top( $new_name );
  $tree->add_node_to_top( $new_name, $new_ref );

Also see L</add_node_to_parent_ref>, L</add_node_to_name>

=head2 add_node_to_name

  $tree->add_node_to_name( $parent_name, $name );
  $tree->add_node_to_name( $parent_name, $name, $new_ref );

Adds an empty or specified node to the specified parent name.

For example:

  $tree->add_node_to_top( 'MyHub1' );
  $tree->add_node_to_name( 'MyHub1', 'MyLeafA' );

  ## Existing nodes under our new node
  my $new_node = [ 'MyLeafB' => [] ];
  $tree->add_node_to_name( 'MyHub1', 'MyHub2', $new_node );

=head2 as_hash

  my $hash_ref = $tree->as_hash;
  my $hash_ref = $tree->as_hash( $parent_ref );

Get a (possibly deep) HASH describing the state of the tree underneath 
the specified parent reference, or the entire tree if none is specified.

For example:

  my $hash_ref = $tree->as_hash( $self->child_node_for('MyHub1') );

Also see L</child_node_for>

=head2 as_list

  my @tree = $tree->as_list;
  my @tree = $tree->as_list( $parent_ref );

Returns the tree in list format.

Not useful for most purposes and may be removed.

=head2 child_node_for

  my $child_node = $tree->child_node_for( $parent_name );
  my $child_node = $tree->child_node_for( $parent_name, $start_ref );

Finds and returns the named child node from the tree.

Starts at the root of the tree or the specified parent reference; also 
see L</trace_indexes>

=head2 del_node_by_name

  $tree->del_node_by_name( $parent_name );
  $tree->del_node_by_name( $parent_name, $start_ref );

Finds and deletes the named child from the tree.

Returns the deleted node.

=head2 names_beneath

  my $names = $tree->names_beneath( $parent_name );
  my $names = $tree->names_beneath( $parent_ref );

Return an arrayref of all names in the tree beneath the specified parent 
node.

Takes either the name of a node in the tree or a reference to a node.

=head2 print_map

  $tree->print_map;
  $tree->print_map( $start_ref );

Prints a visualization of the network map to STDOUT.

=head2 trace_names

  my $names = $tree->trace_names( $parent_name );
  my $names = $tree->trace_names( $parent_name, $start_ref );

Returns an arrayref of the names of every hop in the path to the 
specified parent name.

Starts tracing from the root of the tree unless a parent node reference 
is also specified.

The last hop returned is the target's name.

=head2 trace_indexes

Primarily intended for internal use. This is the breadth-first search 
that other methods use to find a node. There is nothing very useful you 
can do with this externally except count hops; it is documented here to 
show how this tree works.

Returns an arrayref consisting of the index of every hop taken to get to 
the node reference belonging to the specified node name starting from 
the root of the tree or the specified parent node reference.

Given a network:

  hubA
    leafA
    leafB
    hubB
      leafC
      leafD

C<<trace_indexes(B<'leafD'>)>> would return:

  [ 1, 5, 1 ]

These are the indexes into the node references (arrays) owned by each 
hop, including the last hop. Retrieving their names requires 
subtracting one from each index; L</trace_names> handles this.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
