use Test::More;
use strict; use warnings FATAL => 'all';

use IRC::Server::Pluggable 'Types';

# FIXME nickname/user/host need thorough testing,
#  these regexen aren't very well-vetted

ok( !is_InetProtocol(1), 'InetProtocol reject' );
ok( is_InetProtocol(4), 'InetProtocol(4)' );
ok( is_InetProtocol(6), 'InetProtocol(6)' );

ok( ! is_CaseMap('abc'), 'CaseMap reject' );
ok( is_CaseMap('rfc1459'), 'CaseMap rfc1459' );
ok( is_CaseMap('strict-rfc1459'), 'CaseMap strict-rfc1459' );
ok( is_CaseMap('ascii'), 'CaseMap ascii' );

done_testing;
