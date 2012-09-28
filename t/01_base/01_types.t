use Test::More tests => 11;
use strict; use warnings FATAL => 'all';

require POE::Wheel;

use POE qw/
  Filter::Line
/;
## Protocol creates a Session in BUILD
## Silence warnings from POE about lack of run()
POE::Kernel->run;

BEGIN {
  use_ok( 'IRC::Server::Pluggable::Types' );
}

ok( is_Str('abc'), 'Have base type Str' );
ok( is_Num(1), 'Have base type Num' );

{
  package
    MockWheel;
  our @ISA = 'POE::Wheel';
  sub new { bless [], shift }
}
ok( is_InstanceOf(MockWheel->new, 'POE::Wheel'), 'InstanceOf accept' );

ok( !is_InetProtocol(1), 'InetProtocol reject' );
ok( is_InetProtocol(4), 'InetProtocol(4)' );
ok( is_InetProtocol(6), 'InetProtocol(6)' );

ok( ! is_CaseMap('abc'), 'CaseMap reject' );
ok( is_CaseMap('rfc1459'), 'CaseMap rfc1459' );
ok( is_CaseMap('strict-rfc1459'), 'CaseMap strict-rfc1459' );
ok( is_CaseMap('ascii'), 'CaseMap ascii' );
