package IRC::Server::Pluggable::IRC::Mode;
## A single mode.

use 5.12.1;
use strictures 1;
use Carp;

use overload
  bool     => sub { 1 },
  '""'     => 'as_string',
  fallback => 1;

sub FLAG  () { 0 }
sub MODE  () { 1 }
sub PARAM () { 2 }

use namespace::clean;

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
