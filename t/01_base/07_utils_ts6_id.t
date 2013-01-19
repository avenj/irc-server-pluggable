use Test::More; use Test::Exception;
use strict; use warnings FATAL => 'all';

use IRC::Server::Pluggable::Utils::TS::ID;

my $id = ts6_id;
isa_ok( $id, 'IRC::Server::Pluggable::Utils::TS::ID' );

cmp_ok( length($id), '==', 6, 'six character ID' );
my $cur = "$id";
cmp_ok( $cur, 'eq', $id->as_string, 'stringification' );
cmp_ok( $cur, 'ne', $id->next, 'next returned fresh ID' );

my @ids = map {; $id->next } 1 .. 50_000;
my %seen;
@ids = grep {; !$seen{$_}++ } @ids;
cmp_ok( @ids, '==', 50_000, 'created 50k unique IDs' );

my $dies = ts6_id( 'Z99999' );
dies_ok(sub { $dies->next }, 'dies when IDs run dry' );

done_testing;
