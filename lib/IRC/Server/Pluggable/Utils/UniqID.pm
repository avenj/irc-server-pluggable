package IRC::Server::Pluggable::Utils::UniqID;
use strictures 1;
use Carp;

use namespace::clean;
use overload
  '""' => 'as_string',
  fallback => 1;
  ## FIXME overload numeric equality, numeric increment?

sub new {
  my ($class, $start) = @_;
  my $self = [ split '', ($start || 'AAAAAA' ) ];
  bless $self, $class
}

sub as_string {
  my ($self) = @_;
  join '', @$self
}

sub next {
  my ($self) = @_;

  my $pos = @$self;
  while (--$pos) {
    if ($self->[$pos] eq 'Z') {
      $self->[$pos] = 0;
      return $self->as_string
    } elsif ($self->[$pos] ne '9') {
      $self->[$pos]++;
      return $self->as_string
    } else {
      $self->[$pos] = 'A';
    }
  }

  if ($self->[0] eq 'Z') {
    ## We're fucked.
    confess "Ran out of IDs at ".$self->as_string
  } else {
    $self->[$pos]++
  }

  $self->as_string
}

1;
