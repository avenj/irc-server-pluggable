use Test::More;
use strict; use warnings FATAL => 'all';

my $evtype = 'IRC::Server::Pluggable::IRC::Event';

use_ok( 'IRC::Server::Pluggable::IRC::EventSet' );
use_ok( $evtype );
my $evset = new_ok( 'IRC::Server::Pluggable::IRC::EventSet' );

ok( $evset->push( 
    $evset->new_event(
      command => 'PRIVMSG',
      prefix  => 'someuser',
      params  => [ 'target', 'text' ],
    ),
    $evset->new_event(
      command => 'NOTICE',
      prefix  => 'somewhere',
      params  => [ 'target', 'text' ],
    ),
  ), 'push() and new_event()'
);

cmp_ok( $evset->has_events, '==', 2, 'has_events 2' );
my $cloned;
ok( $cloned = $evset->clone, 'clone()' );
cmp_ok( $cloned->has_events, '==', 2, 'cloned set has_events 2' );

my ($one, $two);
isa_ok( $one = $evset->shift, $evtype, 'shift()' );
isa_ok( $two = $evset->pop, $evtype, 'pop()' );
cmp_ok( $one->command, 'eq', 'PRIVMSG', 'first event looks OK' );
cmp_ok( $two->command, 'eq', 'NOTICE', 'second event looks OK' );
ok( !$evset->has_events, 'empty eventset after shift and pop' );

ok( $evset->combine($cloned), 'combine()' );
cmp_ok( $evset->has_events, '==', 2, 'has_events 2 after combine()' );

isa_ok( eventset(), 'IRC::Server::Pluggable::IRC::EventSet',
  'eventset() shortcut returned obj'
);
my $f_ev;
isa_ok( $f_ev = eventset()->combine($evset, $cloned),
  'IRC::Server::Pluggable::IRC::EventSet',
  'eventset->combine() returned obj'
);
cmp_ok( $f_ev->by_index(0)->command, 'eq', 'PRIVMSG',
  'eventset->combine() first ev looks ok'
);

## FIXME these tests are incomplete

done_testing;
