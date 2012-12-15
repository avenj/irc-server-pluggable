use Test::More;
use strict; use warnings FATAL => 'all';

BEGIN {
  use_ok( 'IRC::Server::Pluggable::Utils' );
}

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


## normalize_mask
cmp_ok( normalize_mask('avenj'), 'eq', 'avenj!*@*',
  'normalize_mask with nick only looks ok'
);
cmp_ok( normalize_mask('*@*'), 'eq', '*!*@*',
  'normalize_mask with wildcard mask looks ok'
);
cmp_ok( normalize_mask('*avenj@*'), 'eq', '*!*avenj@*',
  'normalize_mask with partial mask looks ok'
);


## matches_mask
ok( matches_mask('*!*@*', 'avenj!avenj@oppresses.us'),
  'matches_mask( *!*@* ) ok'
);
ok( matches_mask('*!avenj@oppresses.us', 'avenj!avenj@oppresses.us'),
  'matches_mask( *!avenj@oppresses.us ) ok'
);
ok( !matches_mask('nobody!nowhere@*', 'avenj!avenj@oppresses.us'),
  'negative matches_mask ok'
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
