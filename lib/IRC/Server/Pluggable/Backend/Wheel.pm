package IRC::Server::Pluggable::Backend::Wheel;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable::Types;


has 'alarm_id' => (
  ## Idle alarm ID.
  lazy => 1,

  isa => Defined,
  is  => 'rw',

  predicate => 'has_alarm_id',

  default => sub { 0 },
);


has 'compressed' => (
  ## zlib filter added.
  lazy => 1,

  is  => 'rwp',
  isa => Bool,

  writer => 'set_compressed',

  default => sub { 0 },
);


has 'idle' => (
  ## Idle delay.
  lazy => 1,

  is  => 'rwp',
  isa => Num,

  default => sub { 180 },
);


has 'is_client' => (
  is  => 'rw',
  isa => Bool,
  default => sub { 0 },
);


has 'is_peer' => (
  is => 'rw',
  isa => Bool,
  default => sub { 0 },
);


has 'is_disconnecting' => (
  ## Bool or string (disconnect message)
  is  => 'rw',
  default => sub { 0 },
);


has 'is_pending_compress' => (
  ## Wheel needs zlib filter after a socket flush.
  isa => Bool,
  is  => 'rw',
  default => sub { 0 },
);


has 'pass' => (
  ## Specified PASS in pre-registration for this connection.
  lazy => 1,

  isa  => Defined,
  is   => 'rw',

  predicate => 'has_pass',
  writer    => 'set_pass',
  clearer   => 'clear_pass',
);


has 'peeraddr' => (
  required => 1,

  isa => Str,
  is  => 'ro',

  writer => 'set_peeraddr',
);


has 'peerport' => (
  required => 1,

  isa => Int,
  is  => 'ro',

  writer => 'set_peerport',
);


has 'protocol' => (
  ## 4 or 6.
  required => 1,

  isa => InetProtocol,
  is  => 'ro',
);


has 'seen' => (
  ## TS of last activity on this wheel.
  lazy => 1,

  isa => Num,
  is  => 'rw',

  default => sub { 0 },
);


has 'sockaddr' => (
  required => 1,

  isa => Str,
  is  => 'ro',

  writer => 'set_sockaddr',
);


has 'sockport' => (
  required => 1,

  isa => Int,
  is  => 'ro',

  writer => 'set_sockport',
);


has 'wheel_id' => (
  ## Actual POE wheel ID.
  lazy => 1,

  isa => Defined,
  is  => 'ro',

  writer => 'set_wheel_id',
);


has 'wheel' => (
  ## Actual POE::Wheel
  required => 1,

  isa => Wheel,
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

IRC::Server::Pluggable::Backend::Wheel - Connected Wheel details

=head1 SYNOPSIS

FIXME

=head1 DESCRIPTION

These objects contain details regarding connected socket 
L<POE::Wheel::ReadWrite> wheels managed by 
L<IRC::Server::Pluggable::Backend>.

=head2 alarm_id

Connected socket wheels normally have a POE alarm ID attached for an idle 
timer. Writable attribute.

=head2 compressed

Set to true if the Zlib filter has been added.

Use B<set_compressed> to change.

=head2 idle

Idle time used for connection check alarms.

=head2 is_disconnecting

Boolean false if the Wheel is not in a disconnecting state; if it is 
true, it is the disconnect message:

  $obj->is_disconnecting("Client quit")

=head2 is_client

Boolean true if the connection wheel has been marked as a client.

=head2 is_peer

Boolean true if the connection wheel has been marked as a peer.

=head2 is_pending_compress

Boolean true if the Wheel needs a Zlib filter.

  $obj->is_pending_compress(1)

=head2 peeraddr

The remote peer address.

=head2 peerport

The remote peer port.

=head2 seen

Timestamp; should be updated when traffic is seen from this Wheel:

  ## In an input handler
  $obj->seen( time )

=head2 sockaddr

Our socket address.

=head2 sockport

Our socket port.

=head2 wheel

The L<POE::Wheel::ReadWrite> wheel instance.

=head2 wheel_id

The (last known) wheel ID.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
