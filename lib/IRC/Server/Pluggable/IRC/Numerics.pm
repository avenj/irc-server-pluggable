package IRC::Server::Pluggable::IRC::Numerics;

## Base class for numeric responses.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable::Types;

has 'path' => (
  lazy => 1,
  is   => 'ro',
  isa  => Str,
  predicate => 'has_path',
  writer    => 'set_path',
);

has 'rpl_map' => (
  lazy => 1,
  is   => 'ro',
  isa  => HashRef,
  writer  => 'set_rpl_map',
  builder => '_build_rpl_map',
);


sub _build_rpl_map {
  my ($self) = @_;

  my %rplmap;

  if ($self->has_path) {
    ## Read from path.
    open my $fh, '<', $self->path
      or confess "Could not open path ".$self->path.": $!";

    while (my $line = readline($fh) ) {
      ##  <NUMERIC> <STR>    
      my ($num, @str) = split ' ', $line;
      next unless @str;
      $rplmap{$num} = join ' ', @str;
    }

    close $fh;
  } else {
     %rplmap = (
      401 => 'No such nick/channel',
      402 => 'No such server',
      403 => 'No such channel',
      404 => 'Cannot send to channel',
      ## FIXME
    )
  }

  {%rplmap}
}

sub to_str {
  my ($self, $numeric, @params) = @_;

  unless (defined $self->rpl_map->{$numeric}) {
    carp "to_str() called for unknown numeric $numeric";
    return
  }

  sprintf( $self->rpl_map->{$numeric}, @_ )
}




q{
 <Gilded> Has he done this before? 
 <Gilded> Is vandalizing AT&T boxes his... calling?
 <Gilded> I'll show myself out.
};
