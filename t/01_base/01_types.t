use Test::More tests => 22;
use strict; use warnings FATAL => 'all';

use POE qw/
  Filter::Line
/;
## Protocol creates a Session in BUILD
## Silence warnings from POE about lack of run()
POE::Kernel->run;

BEGIN {
  use_ok( 'IRC::Server::Pluggable::Backend' );
  use_ok( 'IRC::Server::Pluggable::Protocol' );
  use_ok( 'IRC::Server::Pluggable::Types' );
}

ok( is_Str('abc'), 'Have base type Str' );
ok( is_Num(1), 'Have base type Num' );

ok( !is_Filter(1), 'Filter reject' );
ok( is_Filter( POE::Filter::Line->new() ), 'Filter accept' );

ok( !is_Wheel(1), 'Wheel reject' );
{
  package
    MockWheel;
  our @ISA = 'POE::Wheel';
  sub new { bless [], shift }
}
ok( is_Wheel( MockWheel->new ), 'Wheel accept' );

ok( !is_InetProtocol(1), 'InetProtocol reject' );
ok( is_InetProtocol(4), 'InetProtocol(4)' );
ok( is_InetProtocol(6), 'InetProtocol(6)' );

ok( ! is_BackendClass(1), 'Backend reject' );
ok(
  is_BackendClass(
    new_ok(
      'IRC::Server::Pluggable::Backend' => [
      ],
    ),
  ),
  'BackendClass accept'
);

ok( ! is_ProtocolClass(1), 'ProtocolClass reject' );
ok(
  is_ProtocolClass(
    new_ok(
      'IRC::Server::Pluggable::Protocol' => [
      ],
    )
  ),
  'ProtocolClass accept'
);

ok( ! is_CaseMap('abc'), 'CaseMap reject' );
ok( is_CaseMap('rfc1459'), 'CaseMap rfc1459' );
ok( is_CaseMap('strict-rfc1459'), 'CaseMap strict-rfc1459' );
ok( is_CaseMap('ascii'), 'CaseMap ascii' );
