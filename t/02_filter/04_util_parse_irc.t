use Test::More;
use strict; use warnings FATAL => 'all';

use_ok( 'IRC::Server::Pluggable::Utils::Parse::IRC' );

my $ref = irc_ref_from_line(
  ":avenj PRIVMSG #otw :Things and stuff.",
);

ok( ref $ref eq 'HASH', 'irc_ref_from_line returned HASH' );
cmp_ok( $ref->{prefix}, 'eq', 'avenj', 'prefix is avenj' );
cmp_ok( $ref->{command}, 'eq', 'PRIVMSG', 'command is PRIVMSG' );
cmp_ok( ref $ref->{params}, 'eq', 'ARRAY', 'params isa ARRAY' );
cmp_ok( $ref->{params}->[0], 'eq', '#otw', 'first param is #otw' );

done_testing;
