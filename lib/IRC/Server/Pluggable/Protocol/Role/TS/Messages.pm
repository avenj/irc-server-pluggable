package IRC::Server::Pluggable::Protocol::Role::TS::Messages;

use Moo::Role;
use strictures 1;

use namespace::clean -except => 'meta';

sub cmd_from_client_privmsg {}
sub cmd_from_client_notice {}

sub cmd_from_peer_privmsg {}
sub cmd_from_peer_notice {}


1;
