use Test::More tests => 7;
use strict; use warnings qw/FATAL all/;

BEGIN {
 use_ok 'IRC::Server::Pluggable::IRC::Filter';
}
my $filter = IRC::Server::Pluggable::IRC::Filter->new;

isa_ok( $filter, 'POE::Filter' );

my $basic = ':test!me@test.ing PRIVMSG #Test :This is a test';
for my $event (@{ $filter->get([ $basic ]) }) {
  cmp_ok( $event->{prefix}, 'eq', 'test!me@test.ing', 'prefix looks ok' );
  cmp_ok( $event->{command}, 'eq', 'PRIVMSG', 'command looks ok' );
  cmp_ok( $event->{params}->[0], 'eq', '#Test', 'param 0 looks ok' );
  cmp_ok( $event->{params}->[1], 'eq', 'This is a test', 'param 1 looks ok' );
  for my $parsed (@{ $filter->put([ $event ]) }) {
    cmp_ok($parsed, 'eq', $basic, 'put() looks ok' );
  }
}
