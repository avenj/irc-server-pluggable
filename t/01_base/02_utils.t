use Test::More;
use strict; use warnings FATAL => 'all';

## FIXME Backend::Utils tests should be split out
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
  use_ok( 'IRC::Server::Pluggable::Utils' );
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


## lc_irc / uc_irc
is(
  lc_irc("ABC[]", "ascii"),
  "abc[]",
  "lc_irc ascii"
);
is(
  uc_irc("abc[]", "ascii"),
  "ABC[]",
  "uc_irc ascii"
);

is(
  lc_irc("Nick^[Abc]", "strict-rfc1459"),
  "nick^{abc}",
  "lc_irc strict-rfc1459"
);
is(
  uc_irc("nick^{abc}", "strict-rfc1459"),
  "NICK^[ABC]",
  "uc_irc strict-rfc1459"
);

is(
  lc_irc('Nick~[A\bc]'),
  'nick^{a|bc}',
  "lc_irc rfc1459"
);
is(
  uc_irc('Nick^{a|bc}'),
  'NICK~[A\BC]',
  "uc_irc rfc1459"
);

## parse_user
is( 
  my $nick = parse_user('SomeNick!user@my.host.org'),
  "SomeNick",
  "parse_user (scalar)"
);

is_deeply(
  [ parse_user('SomeNick!user@my.host.org') ],
  [ 'SomeNick', 'user', 'my.host.org' ],
  "parse_user (list)"
);


## mode_to_array
is_deeply(
  mode_to_array( '+kl-t',
    params => [ 'key', 10 ],
    param_always => [ split //, 'bkov' ],
    param_set    => [ 'l' ],
  ),
  [
    [ '+', 'k', 'key' ],
    [ '+', 'l', 10 ],
    [ '-', 't' ],
  ],
);
my $array = mode_to_array( '+o-o+vb avenj avenj Joah things@stuff' );
is_deeply( $array,
  [
    [ '+', 'o', 'avenj' ],
    [ '-', 'o', 'avenj' ],
    [ '+', 'v', 'Joah'  ],
    [ '+', 'b', 'things@stuff' ],
  ],
) or diag explain $array;

## mode_to_hash
my $mhash;
ok( $mhash = mode_to_hash(  '+ot-k+l',
    params => [ qw/SomeUser thiskey 10/ ],
  ), 'mode_to_hash() (default param_ opts)'
);

is_deeply( $mhash,
  {
    add => {
      'o' =>
        [ 'SomeUser' ],
      't' => 1,
      'l' =>
        [ 10 ],
    },
    del => {
      'k' => [ 'thiskey' ],
    },
  },
);

ok( $mhash = mode_to_hash(  '+h',
    params => [ 'SomeUser' ],
    param_always => [ 'h' ],
  ), 'mode_to_hash() (custom param_always)'
);

is_deeply( $mhash,
  {
    add => {
      'h' => [ 'SomeUser' ],
    },
    del => { },
  },
);


done_testing;
