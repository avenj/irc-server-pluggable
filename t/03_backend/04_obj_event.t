use Test::More tests => 3;
use strict; use warnings FATAL => 'all' ;

BEGIN {
  use_ok( 'IRC::Server::Pluggable::IRC::Event' );
  use_ok( 'IRC::Server::Pluggable::Backend' );
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
