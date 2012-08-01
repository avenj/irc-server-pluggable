package IRC::Server::Pluggable::Backend::Wheel;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable::Types;

has 'compressed' => (
  lazy => 1,

  is  => 'rwp',
  isa => Bool,

  writer => 'set_compressed',

  default => sub { 0 },
);

has 'is_disconnecting' => (
  is  => 'rw',
  default => sub { 0 },
);

has 'is_pending_compress' => (
  isa => Bool,
  is  => 'rw',
  default => sub { 0 },
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
  required => 1,
  
  isa => InetProtocol,
  is  => 'ro',
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

has 'wheel' => (
  required => 1,

  isa => Wheel,
  is  => 'ro',
  
  clearer => 'clear_wheel',
  writer  => 'set_wheel',
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

=head2 compressed

Set to true if the Zlib filter has been added.

Use B<set_compressed> to change.

=head2 is_disconnecting

Boolean false if the Wheel is not in a disconnecting state; if it is 
true, it is the disconnect message:

  $obj->is_disconnecting("Client quit")

=head2 is_pending_compress

Boolean true if the Wheel needs a Zlib filter.

  $obj->is_pending_compress(1)

=head2 peeraddr

The remote peer address.

=head2 peerport

The remote peer port.

=head2 sockaddr

Our socket address.

=head2 sockport

Our socket port.

=head2 wheel

The L<POE::Wheel::ReadWrite> wheel instance.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
