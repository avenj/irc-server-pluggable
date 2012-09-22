package IRC::Server::Pluggable::Protocol::Role::TS::Messages;

use Moo::Role;
use strictures 1;

use IRC::Server::Pluggable qw/
  Backend::EventSet
/;


use namespace::clean -except => 'meta';


requires qw/
  config
  send_to_routes
/;

sub _r_msgs_accumulate_targets {
  ## FIXME
  ##  Iterate target list
  ##  Do hybrid-ish things
  ##  Accumulate an EventSet
}

sub _r_msgs_can_send_to_nick {

}

sub _r_msgs_can_send {
  ## FIXME
  ##  For a channel, Role::Channels provides user_can_send_to_chan
  ##  Should we provide user_can_send_to_user ?
}


sub cmd_from_client_privmsg {}
sub cmd_from_client_notice {}

sub cmd_from_peer_privmsg {}
sub cmd_from_peer_notice {}


1;
