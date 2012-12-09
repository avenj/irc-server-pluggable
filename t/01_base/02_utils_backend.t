use Test::More;
use strict; use warnings FATAL => 'all';

use Socket qw/
  pack_sockaddr_in
  pack_sockaddr_in6
  inet_aton
  inet_pton
  AF_INET
  AF_INET6
/;

BEGIN {
  use_ok( 'IRC::Server::Pluggable::Backend::Utils' );
}


## get_unpacked_addr
my $packed_v4 = pack_sockaddr_in( 6667, 
  inet_aton('127.0.0.1')
);
my $packed_v6 = pack_sockaddr_in6( 6666,
  inet_pton(AF_INET6, 'fe80::1')
);

my ($family, $addr, $port) = get_unpacked_addr( $packed_v4 );
is( $family, 4 );
is( $addr, '127.0.0.1' );
is( $port, 6667 );

($family, $addr, $port) = get_unpacked_addr( $packed_v6 );
is( $family, 6 );
is( $addr, 'fe80::1' );
is( $port, 6666 );


done_testing;
