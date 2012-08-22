package IRC::Server::Pluggable::Backend::Connector;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable::Types;

has 'addr' => (
  required => 1,

  isa => Str,
  is  => 'ro',

  writer => 'set_addr',
);

has 'bindaddr' => (
  lazy => 1,

  isa => Str,
  is  => 'ro',

  predicate => 'has_bindaddr',
  writer    => 'set_bindaddr',

  default => sub { '' },
);

has 'args' => (
  lazy => 1,

  isa => Defined,
  is  => 'ro',

  writer => 'set_args',

  default => sub { {} },
);

has 'port' => (
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

has 'ssl' => (
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

  isa => Wheel,
  is  => 'ro',

  clearer => 'clear_wheel',
  writer  => 'set_wheel',

  trigger => sub {
    my ($self, $wheel) = @_;
    $self->set_wheel_id( $wheel->ID )
  },
);

q{
 <HoopyCat> NEVER
 <HoopyCat> PUT SALT IN
 <HoopyCat> YOUR EYE
 * HoopyCat wanders off to hack a highway message sign
};

=pod

=head1 NAME

IRC::Server::Pluggable::Backend::Connector - Connector socket details

=head1 SYNOPSIS

  my $connector = IRC::Server::Pluggable::Backend::Connector->new(
    addr  => $remoteaddr,
    port  => $remoteport,
    wheel => $wheel,      ## SocketFactory Wheel
    protocol => 6,        ## 4 or 6
    
    ## Optional:
    bindaddr => $localaddr,
    ssl => 1,

    ## Any extra args specified will be added to args() attrib
  );

=head1 DESCRIPTION

These objects contain details regarding 
L<IRC::Server::Pluggable::Backend> outgoing connector sockets.

All of these attributes can be set via C<set_$attrib> :

=head2 addr

The remote address this Connector is intended for; also see L</port>

=head2 bindaddr

The local address this Connector should bind to.

=head2 args

Extra arguments specified in Connector construction, as a HASH.

=head2 port

The remote port this Connector is intended for; also see L</addr>

=head2 protocol

The Internet protocol version this Connector was spawned for; either 4 or 
6.

=head2 ssl

Boolean value indicating whether or not this Connector should be 
SSLified at connect time.

=head2 wheel

The L<POE::Wheel::SocketFactory> for this Connector.

=head2 wheel_id

The (last known) wheel ID.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
