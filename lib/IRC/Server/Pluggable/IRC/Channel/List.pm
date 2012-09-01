package IRC::Server::Pluggable::IRC::Channel::List;

## Base class for lists for a channel (f.ex banlists)

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable::Types;
use IRC::Server::Pluggable::Utils qw/
  lc_irc
  matches_mask
  normalize_mask
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

sub items {
  my ($self) = @_;

  wantarray ?
    ( keys %{ $self->_list } )
    : [ keys %{ $self->_list } ]
}

sub keys_matching_regex {
  my ($self, $regex) = @_;

  my @resultset = grep { $_ =~ $regex } keys %{ $self->_list };

  wantarray ?
    @resultset : \@resultset
}

sub keys_matching_ircstr {
  my ($self, $ircstr, $casemap) = @_;

  my $lower = lc_irc($ircstr, $casemap);
  my @resultset =
    grep {
      lc_irc($_, $casemap) eq $lower
    } keys %{ $self->_list };

  wantarray ?
    @resultset : \@resultset
}

sub keys_matching_mask {
  my ($self, $mask, $casemap) = @_;

  $mask = normalize_mask($mask);

  my @resultset = grep {
    matches_mask( $mask, $_, $casemap )
  } keys %{ $self->_list };

  wantarray ?
    @resultset : \@resultset
}

sub keys_matching_host {
  my ($self, $host, $casemap) = @_;

  ## Does NOT normalize listed masks
  ## This is up to the subclass at add-time.
  my @resultset = grep {
    matches_mask( $_, $host, $casemap )
  } keys %{ $self->_list };

  wantarray ?
    @resultset : \@resultset
}

1;

## FIXME POD is out of date

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

=head3 items

  for my $key ( $list->items ) {
    . . .
  }

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
