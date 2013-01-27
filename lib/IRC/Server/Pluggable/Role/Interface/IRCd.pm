package IRC::Server::Pluggable::Role::Interface::IRCd;
## Interface looks like an IRCd.
use strictures 1;
use Moo::Role;

with 'IRC::Server::Pluggable::Role::Interface::Emitter';

requires qw/
  config

  disconnect

  equal
  lower
  upper

  channels
  peers
  users

  send_numeric
  send_to_targets
/;

1;
