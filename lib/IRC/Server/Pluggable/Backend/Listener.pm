package IRC::Server::Pluggable::Backend::Listener;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable::Types;

use namespace::clean -except => 'meta';


has 'addr'  => (
  required => 1,

  isa => Str,
  is  => 'ro',

  writer => 'set_addr',
);

has 'idle'  => (
  lazy => 1,

  isa => Num,
  is  => 'rw',

  ## FIXME?

  predicate => 'has_idle',
  writer    => 'set_idle',

  default => sub { 0 },
);

has 'port'  => (
  required => 1,

  isa => Int,
  is  => 'ro',

  writer => 'set_port',
);

has 'protocol' => (
  required => 1,

  isa => InetProtocol,
  is  => 'ro',

  writer => 'set_protocol',
);

has 'ssl'   => (
  isa => Bool,
  is  => 'ro',

  predicate => 'has_ssl',
  writer    => 'set_ssl',

  default => sub { 0 },
);

has 'wheel_id' => (
  lazy => 1,

  isa => Defined,
  is  => 'ro',

  writer => 'set_wheel_id',
);

has 'wheel' => (
  required => 1,

  isa => ObjectIsa['POE::Wheel'],
  is  => 'ro',

  clearer => 'clear_wheel',
  writer  => 'set_wheel',

  trigger => sub {
    my ($self, $wheel) = @_;
    $self->set_wheel_id( $wheel->ID )
  },
);

1;

=pod

=head1 NAME

IRC::Server::Pluggable::Backend::Listener - Listener socket details

=head1 SYNOPSIS

  my $listener = IRC::Server::Pluggable::Backend::Listener->new(
    addr  => $local_addr,
    port  => $local_port,
    wheel => $wheel, ## POE::Wheel::SocketFactory
    protocol => 4,   ## 4 or 6
    
    ## Optional:
    ssl => 1,
  );

=head1 DESCRIPTION

These objects contain details regarding 
L<IRC::Server::Pluggable::Backend> Listener sockets.

=head2 addr

The local address to bind to.

=head2 port

The local port to listen on.

=head2 protocol

The internet protocol version to use for this listener (4 or 6).

=head2 ssl

Boolean value indicating whether or not connections to this listener 
should be SSLified.

=head2 wheel

The L<POE::Wheel::SocketFactory> instance for this listener.

=head2 wheel_id

The (last known) wheel ID.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
