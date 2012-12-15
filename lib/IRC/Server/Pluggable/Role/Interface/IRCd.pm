package IRC::Server::Pluggable::Role::Interface::IRCd;
## Interface looks like an IRCd.
use strictures 1;
use Moo::Role;

with 'IRC::Server::Pluggable::Role::Interface::Emitter';

requires qw/
  channels
  config
  disconnect
  numeric
  peers
  send_to_routes
  users
/;

1;
