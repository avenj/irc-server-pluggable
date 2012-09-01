package IRC::Server::Pluggable::Role::Peers;


## Handles:
##  irc_ev_peer_numeric
##  irc_ev_peer_cmd_server
##  irc_ev_peer_cmd_squit

use strictures 1;
use Moo::Role;

sub ROLES () {
  'IRC::Server::Pluggable::Protocol::Role::Peers::'
}


sub irc_ev_peer_cmd_server {}
sub irc_ev_peer_cmd_squit  {}

sub irc_ev_peer_numeric {
  ## Numeric from peer intended for a client; route it.
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $ev)     = @_[ARG0, ARG1];

  my $target_nick  = $ev->params->[0];
  my $target_user  = $self->users->by_name($target_nick);

  $self->send_to_route( $ev, $target_user->route );
}


1;
