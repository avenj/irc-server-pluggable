use Test::More tests => 6;
use strict; use warnings FATAL => 'all';

use POE::Filter::Line;

BEGIN {
  use_ok( 'IRC::Server::Pluggable::Types' );
}

ok( is_Str('abc'), 'Have base type Str' );
ok( is_Num(1), 'Have base type Num' );

ok( !is_Filter(1), 'Filter reject' );
ok( !is_Wheel(1), 'Wheel reject' );

ok( is_Filter( POE::Filter::Line->new() ), 'Filter accept' );
