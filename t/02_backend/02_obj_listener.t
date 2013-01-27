use Test::More tests => 8;
use strict; use warnings FATAL => 'all';

{
  package
    MockWheel;  
  require POE::Wheel;
  our @ISA = qw/POE::Wheel/;
  sub ID  { 1 }
  sub new { bless [], shift }
}

BEGIN {
  use_ok( 'IRC::Server::Pluggable::Backend::Listener' );
}

my $obj = new_ok( 'IRC::Server::Pluggable::Backend::Listener' => [
    addr => '127.0.0.1',
    port => 6667,
    protocol => 4,
    ssl   => 1,
    wheel => MockWheel->new,
  ],
);

is( $obj->addr, '127.0.0.1' );
is( $obj->port, 6667 );
is( $obj->protocol, 4 );
ok( $obj->ssl, 'ssl()' );
isa_ok( $obj->wheel, 'POE::Wheel', 'wheel()' );
is( $obj->wheel_id, 1 );
