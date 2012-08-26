use Test::More tests => 10;
use strict; use warnings FATAL => 'all';

{
  package
    MockWheel;  
  require POE::Wheel;
  our @ISA = qw/POE::Wheel/;
  sub ID { 1 }
  sub new { bless [], shift }
}

BEGIN {
  use_ok( 'IRC::Server::Pluggable::Backend::Connect' );
}

my $obj = new_ok( 'IRC::Server::Pluggable::Backend::Connect' => [
    protocol => 4,
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
is( $obj->wheel_id, 1 );

ok( !$obj->is_disconnecting, 'not is_disconnecting' );
ok( $obj->is_disconnecting("Client quit"), "is_disconnecting()" );


