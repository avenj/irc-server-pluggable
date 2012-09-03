## Handles:

  ## irc_ev_client_cmd_privmsg
  ## irc_ev_client_cmd_notice
  ## irc_ev_peer_cmd_notice
  ## irc_ev_peer_cmd_privmsg
  ##  others ?

use namespace::clean -except => 'meta';

sub irc_ev_client_cmd_privmsg {}
sub irc_ev_client_cmd_notice {}

sub irc_ev_peer_cmd_notice {}
sub irc_ev_peer_cmd_privmsg {}


1;
