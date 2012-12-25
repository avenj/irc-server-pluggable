package IRC::Server::Pluggable::Client::Heavy;
use 5.12.1;
use strictures 1;

use Moo;

extends 'IRC::Server::Pluggable::Client::Lite';

after N_irc_351 => sub {
  ## WHO reply
};

after N_irc_mode => sub {

};

after N_irc_join => sub {

};

## FIXME

1;
