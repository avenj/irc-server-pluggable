package IRC::Server::Pluggable::Role::Interface::IRCd;
## Interface looks like an IRCd.
use strictures 1;
use Moo::Role;

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
