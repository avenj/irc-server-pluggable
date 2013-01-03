package IRC::Server::Pluggable::Role::Interface::IRCd;
## Interface looks like an IRCd.
use strictures 1;
use Moo::Role;

with 'IRC::Server::Pluggable::Role::Interface::Emitter';

requires qw/
  channels
  config
  disconnect
  equal
  lower
  numeric
  peers
  send_numeric
  send_to_routes
  upper
  users
/;

1;
