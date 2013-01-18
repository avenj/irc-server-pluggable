package IRC::Server::Pluggable::Utils::UniqID;
use strictures 1;
use Carp;

use namespace::clean;


sub new {
  my ($class, $start) = @_;
  my $self = [ split '', ($start || 'AAAAAA' ) ];
  bless \$self, $class
}

sub next {
  my ($self) = @_;
  my $pos = 6;

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


## FIXME

1;
