use Test::More tests => 1;
use strict; use warnings FATAL => 'all' ;

use POE::Filter::IRCD;

BEGIN {
  use_ok( 'IRC::Server::Pluggable::Backend::Event' );
}

my $obj = new_ok( 'IRC::Server::Pluggable::Backend::Event' => [
    ## FIXME feed me filtered irc line
  ],
);
