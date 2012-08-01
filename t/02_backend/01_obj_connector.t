use Test::More tests => 7;
use strict; use warnings FATAL => 'all';

{
  package
    MockWheel;  
  require POE::Wheel;
  our @ISA = qw/POE::Wheel/;
  my $x;
  sub new { bless [], shift }
  sub ID { ++$x }
}

BEGIN {
  use_ok( 'IRC::Server::Pluggable::Backend::Connector' );
}

my $obj = new_ok( 'IRC::Server::Pluggable::Backend::Connector' => [
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
