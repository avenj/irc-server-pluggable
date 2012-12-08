package IRC::Server::Pluggable::IRC::Mode;

## A single mode change array.

use 5.12.1;
use strictures 1;
use Carp;

sub FLAG  () { 0 }
sub MODE  () { 1 }
sub PARAM () { 2 }

use namespace::clean;

use overload
  bool     => sub { 1 },
  '""'     => 'as_string',
  fallback => 1;


sub new {
  my $class = shift;
  confess "Expected at least a flag and mode"
    unless @_ >= 2;
  bless [ @_ ], $class
}

sub flag  { $_[0]->[FLAG] }
sub char  { $_[0]->[MODE] }
sub param { $_[0]->[PARAM] // () }

sub as_string {
  my ($self) = @_;
  my $str = $self->[FLAG] . $self->[MODE];
  $str .= " ".$self->[PARAM] if defined $self->[PARAM];
  $str
}

1;

=pod

=head1 NAME

IRC::Server::Pluggable::IRC::Mode - A single mode change

=head1 SYNOPSIS

  my $mode = IRC::Server::Pluggable::IRC::Mode->new(
    '+', 'o', 'avenj'
  );

  my $flag = $mode->flag;
  my $mode = $mode->char;
  my $arg  = $mode->param;

=head1 DESCRIPTION

A simple ARRAY-type object representing a single mode change.

Can be used to turn L<IRC::Server::Pluggable::Utils/mode_to_array> mode ARRAYs
into objects:

  for my $mset (@$mode_array) {
    my $this_mode = IRC::Server::Pluggable::IRC::Mode->new(
      @$mset
    );

    . . .
  }

=head2 as_string

Produces a mode string (with params attached) for this single mode change.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
