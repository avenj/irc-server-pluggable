use Test::More;
use strict; use warnings FATAL => 'all' ;

BEGIN {
  use_ok( 'IRC::Server::Pluggable::Backend' );
  use_ok( 'IRC::Server::Pluggable::IRC::Event' );
}

my $backend = IRC::Server::Pluggable::Backend->new;
my $filter = $backend->filter;

my $raw_line = ":server.org 001 user :Welcome to IRC\r\n";
my $arr = $filter->get([$raw_line]);
my $hash = shift @$arr;

my $obj = new_ok( 'IRC::Server::Pluggable::IRC::Event' => [
    %$hash
  ],
);

isa_ok( $obj, 'IRC::Message::Object' );

cmp_ok( $obj->prefix, 'eq', 'server.org', 'prefix looks ok' );
cmp_ok( $obj->command, 'eq', '001', 'command looks ok' );
cmp_ok( $obj->params->[0], 'eq', 'user', 'param 0 looks ok' );
cmp_ok( $obj->params->[1], 'eq', 'Welcome to IRC', 'param 1 looks ok' );

done_testing;
