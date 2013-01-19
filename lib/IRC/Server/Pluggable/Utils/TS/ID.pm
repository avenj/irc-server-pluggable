package IRC::Server::Pluggable::Utils::TS::ID;
use strictures 1;
use Carp;

use Exporter 'import';
our @EXPORT = 'ts6_id';
sub ts6_id {
  __PACKAGE__->new(@_)
}

use overload
  bool => sub { 1 },
  '""' => 'as_string',
  '++' => 'next',
  fallback => 1;


sub new {
  my ($class, $start) = @_;
  my $self = [ split '', $start || 'A'x6 ];
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
    croak "Ran out of IDs after ".$self->as_string
  } else {
    $self->[$pos]++
  }

  $self->as_string
}

1;

=pod

=head1 NAME

IRC::Server::Pluggable::Utils::TS::ID - Generate TS6 IDs

=head1 SYNOPSIS

  use IRC::Server::Pluggable qw/
    Utils::TS::ID
  /;

  my $id = ts6_id;
  my $next_id = $id->next;
  say "First two IDs are $id and $next_id";

=head1 DESCRIPTION

Lightweight array-type objects that can produce sequential TS6 IDs.

The exported B<ts6_id> function will instance a new ID object. B<ts6_id>
optionally takes a start-point as a string (defaults to 'AAAAAA' similar to
C<ratbox>).

Calling B<next> on the produced object will return the next unique identifier. 
If no more IDs are available, B<next> will croak.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>; conceptually derived from the relevant
C<ratbox> function.

=cut
