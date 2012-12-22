package IRC::Server::Pluggable::Role::Interface::Client;
use strictures 1;
use Moo::Role;

requires qw/
  send

  privmsg
  notice
  ctcp

  mode
  join
  part
/;

1;
