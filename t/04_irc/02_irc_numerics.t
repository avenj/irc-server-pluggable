use Test::More;
use strict; use warnings FATAL => 'all';

use_ok( 'IRC::Server::Pluggable::IRC::Numerics' );

my $numerics = new_ok( 'IRC::Server::Pluggable::IRC::Numerics' );

my $hash;
## One param:
ok( $hash = $numerics->to_hash( 401,
       prefix => 'testing',
       target => 'some_nick',
       params => [ 'things' ],
  ), 'to_hash'
);

is_deeply( $hash,
  {
    command => '401',
    prefix  => 'testing',
    params  => [
      'some_nick',
      'things',
      'No such nick/channel'
    ],
  },
  'single param hash looks ok'
);

## Two params:
$hash = $numerics->to_hash( 443,
  prefix => 'testing',
  target => 'some_nick',
  params => [ 'some_user', '#channel' ],
);
is_deeply( $hash,
  {
    command => '443',
    prefix  => 'testing',
    params  => [
      'some_nick',
      'some_user',
      '#channel',
      'is already on channel'
    ],
  }
);

## as an Event:
my $ev;
ok( $ev = $numerics->to_event( 401,
        prefix => 'testing',
        target => 'some_nick',
        params => [ 'things' ],
  ),
  'to_event'
);
isa_ok( $ev, 'IRC::Server::Pluggable::IRC::Event' );
cmp_ok( $ev->command, 'eq', 401, 'command() looks ok' );
cmp_ok( $ev->prefix, 'eq', 'testing', 'prefix() looks ok' );
is_deeply( $ev->params, [ 'some_nick', 'things', 'No such nick/channel' ] );

ok( ref $numerics->get_rpl(401) eq 'ARRAY', 'get_rpl()' );

done_testing;
