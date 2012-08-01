use Test::More tests => 9;
use strict; use warnings FATAL => 'all';

{
  package
    MockWheel;  
  our @ISA = qw/POE::Wheel/;
  my $x;
  sub ID { ++$x }
  sub new { bless [], shift }
}

BEGIN {
  use_ok( 'IRC::Server::Pluggable::Backend::Wheel' );
}

my $obj = new_ok( 'IRC::Server::Pluggable::Backend::Wheel' => [
    peeraddr => '127.0.0.1',
    peerport => 6667,
    sockaddr => '127.0.0.1',
    sockport => 1234,
    wheel => MockWheel->new,
  ],
);

is( $obj->peeraddr, '127.0.0.1' );
is( $obj->peerport, 6667 );
is( $obj->sockaddr, '127.0.0.1' );
is( $obj->sockport, 1234 );
isa_ok( $obj->wheel, 'POE::Wheel' );

ok( !$obj->is_disconnecting, 'not is_disconnecting' );
ok( $obj->is_disconnecting("Client quit"), "is_disconnecting()" );


