use Test::More tests => 3;
use strict; use warnings FATAL => 'all';

use Object::Pluggable::Constants qw/:ALL/;

BEGIN {
 use_ok( 'IRC::Server::Pluggable::Emitter' );
}

is( EAT_NONE, PLUGIN_EAT_NONE, 'EAT_NONE' );
## hmm .. do we care about these two?
#is( EAT_CLIENT, PLUGIN_EAT_CLIENT, 'EAT_CLIENT' );
#is( EAT_PLUGIN, PLUGIN_EAT_PLUGIN, 'EAT_PLUGIN' );
is( EAT_ALL, PLUGIN_EAT_ALL, 'EAT_ALL' );
