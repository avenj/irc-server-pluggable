package IRC::Server::Pluggable::IRC::Event;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable qw/
  IRC::Filter

  Types
/;

use namespace::clean -except => 'meta';


has 'command' => (
  is        => 'ro',
  lazy      => 1,
  isa       => Str,
  predicate => 'has_command',
  writer    => 'set_command',
  default   => sub { '' },
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
    my $lines = $self->__filter->put(
      [
       {
         prefix  => $self->prefix,
         command => $self->command,
         params  => $self->params
       }
      ],
    );
    $lines->[0]
  },
);


has '__filter' => (
  is      => 'rw',
  lazy    => 1,
  builder => '__build_filter',
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

  my $event = IRC::Server::Pluggable::IRC::Event->new(
    prefix   => ':some.server.org',
    command  => '001',
    params   => [ 'user', 'Welcome to IRC' ],
    raw_line => ':some.server.org 001 user :Welcome to IRC',
  );

  ## Can be fed from IRC::Server::Pluggable::IRC::Filter :
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

=head2 command

The parsed command received.

=head2 params

ARRAY of parameters.

=head2 prefix

The server prefix.

=head2 raw_line

The raw IRC line.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
