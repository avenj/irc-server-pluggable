package IRC::Server::Pluggable::IRC::Event;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable qw/
  IRC::Filter
  Types
/;

use Exporter 'import';
our @EXPORT = 'ev';

use namespace::clean -except => 'import';

sub ev {
  __PACKAGE__->new(@_)
}

has 'command' => (
  required  => 1,
  is        => 'ro',
  isa       => Str,
  predicate => 'has_command',
  writer    => 'set_command',
);

has 'prefix' => (
  is        => 'ro',
  lazy      => 1,
  isa       => Str,
  predicate => 'has_prefix',
  writer    => 'set_prefix',
  default   => sub { '' },
);

has 'params' => (
  is        => 'ro',
  lazy      => 1,
  isa       => ArrayRef,
  predicate => 'has_params',
  writer    => 'set_params',
  default   => sub { [] },
);

has 'raw_line' => (
  is        => 'ro',
  lazy      => 1,
  isa       => Str,
  predicate => 'has_raw_line',
  writer    => 'set_raw_line',
  default   => sub {
    my ($self) = @_;
    my %hash;
    for my $key (qw/prefix command params tags/) {
      my $pred = "has_".$key;
      $hash{$key} = $self->$key if $self->$pred;
    }
    my $lines = $self->__filter->put( [ \%hash ] );
    $lines->[0]
  },
);

has 'tags' => (
  is        => 'ro',
  lazy      => 1,
  isa       => HashRef,
  predicate => 'has_tags',
  writer    => 'set_tags',
  default   => sub {  {}  },
);

sub BUILDARGS {
  my $class = shift;
  my %params = @_ > 1 ? @_ : (raw_line => $_[0]) ;

  if (not defined $params{command}) {
    if (defined $params{raw_line}) {
      ## Try to create self from raw_line instead
      my $filt = IRC::Server::Pluggable::IRC::Filter->new;
      my $refs = $filt->get( [$params{raw_line}] );
      %params = %{ $refs->[0] } if @$refs;
    } else {
      confess "Bad params; a command or a raw_line must be specified in new()"
    }
  }

  \%params
}

sub get_tag {
  my ($self, $tag) = @_;
  return unless $self->has_tags and keys %{ $self->tags };
  ## A tag might have an undef value ...
  $self->tags->{$tag}
}

sub tags_as_array {
  my ($self) = @_;
  return [] unless $self->has_tags and keys %{ $self->tags };

  my $tag_array = [];
  while (my ($thistag, $thisval) = each %{ $self->tags }) {
    push @$tag_array,
      defined $thisval ? join '=', $thistag, $thisval
        : $thistag
  }

  $tag_array
}

sub tags_as_string {
  my ($self) = @_;
  return unless $self->has_tags and keys %{ $self->tags };

  my $str;
  my @tags = %{ $self->tags };
  while (my ($thistag, $thisval) = splice @tags, 0, 2) {
    $str .= ( $thistag . 
      ( defined $thisval ? '='.$thisval : '' ) .
      ( @tags ? ';' : '' )
    );
  }

  $str
}


has '__filter' => (
  is       => 'rw',
  init_arg => 'filter',
  lazy     => 1,
  builder  => '__build_filter',
);

sub __build_filter {
  my ($self) = @_;
  IRC::Server::Pluggable::IRC::Filter->new(colonify => 1)
}

no warnings 'void';
q{
 <rnowak> fine, be rude like that
 <Perihelion> SORRY I WAS DISCUSSING THE ABILITY TO PUT
  AN IRCD ON A ROOMBA
};

=pod

=head1 NAME

IRC::Server::Pluggable::IRC::Event - IRC Events

=head1 SYNOPSIS

  ## Feed me a hash:
  my $event = IRC::Server::Pluggable::IRC::Event->new(
    command  => '001',
    prefix   => ':some.server.org',
    params   => [ 'user', 'Welcome to IRC' ],
  );

  ## Or use the 'ev()' shortcut:
  my $event = ev(
    command => '001',
    prefix  => ':some.server.org',
    params  => [ 'user', 'Welcome to IRC' ],
  );

  ## Can take a raw IRC line (and parse it):
  my $event = ev(
    raw_line => ':some.server.org 001 user :Welcome to IRC'
  );

  ## Can be fed from 'IRC::Server::Pluggable::IRC::Filter':
  my $event = IRC::Server::Pluggable::IRC::Event->new(
   %{ $input_hash_from_filter }
  );

=head1 DESCRIPTION

These objects represent IRC events.

These are created by L<IRC::Server::Pluggable::Backend> using 
L<IRC::Server::Pluggable::IRC::Filter> hashes.

They are also used to feed the send() method provided by 
L<IRC::Server::Pluggable::Backend>.

These objects do not do much validation on their own. You can prefix 
attributes with B<has_> to determine whether or not valid input is 
available.

These objects are capable of constructing attributes from a raw IRC line and
vice-versa.

=head2 Functions

=head3 ev

Create a new IRC::Event.

A shortcut for C<< IRC::Server::Pluggable::IRC::Event->new >>

=head2 Methods

=head3 command

The parsed command received.

=head3 params

ARRAY of parameters.

=head3 prefix

The server prefix.

=head3 raw_line

The raw IRC line.

=head3 tags

IRCv3.2 message tags, as a HASH of key-value pairs.

=head3 tags_as_array

IRCv3.2 message tags, as an ARRAY of tags in the form of 'key=value'

=head3 tags_as_string

IRCv3.2 message tags as a specification-compliant string.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
