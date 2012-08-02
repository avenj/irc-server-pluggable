use Test::More tests => 13;
use strict; use warnings FATAL => 'all';

use POE::Filter::Line;

BEGIN {
  use_ok( 'IRC::Server::Pluggable::Backend' );
  use_ok( 'IRC::Server::Pluggable::Types' );
}

ok( is_Str('abc'), 'Have base type Str' );
ok( is_Num(1), 'Have base type Num' );

ok( !is_Filter(1), 'Filter reject' );
ok( !is_Wheel(1), 'Wheel reject' );

ok( is_Filter( POE::Filter::Line->new() ), 'Filter accept' );

ok( !is_InetProtocol(1), 'InetProtocol reject' );
ok( is_InetProtocol(4), 'InetProtocol(4)' );
ok( is_InetProtocol(6), 'InetProtocol(6)' );

ok( ! is_Backend(1), 'Backend reject' );
ok(
  is_Backend(
    new_ok(
      'IRC::Server::Pluggable::Backend' => [
      ],
    ),
  ),
  'Backend accept'
);
