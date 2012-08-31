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

=pod

=head1 NAME

IRC::Server::Pluggable::IRC::Channel::List - Base class for channel lists

=head1 SYNOPSIS

FIXME

=head1 DESCRIPTION

Base class for lists used by L<IRC::Server::Pluggable::IRC::Channel> 
instances, such as ban lists (see 
L<IRC::Server::Pluggable::IRC::Channel::List::Bans).

=head2 Methods

=head3 add

  $list->add( $key, $value );

=head3 del

  $list->del( $key );

=head3 get

  my $item = $list->get( $key );

=head3 keys

  for my $key ( $list->keys ) {
    . . .
  }

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
