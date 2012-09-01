package IRC::Server::Pluggable::Protocol::Role::Ping;

use strictures 1;
use Carp;
use Moo::Role;

requires qw/
  send_to_routes
/;

sub irc_ev_connection_idle {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## A connection is idle.
  ## Might be unknown, user, or peer.
  ## If the conn is not registered yet:
  ##  took too long to register, disconnect with Connection timeout
  ## If the conn has a pending ping already:
  ##  exceeded round-trip time, Ping timeout
  ## Send ping to conn
  ## Set pending ping status
  ## Clear pending ping status if PONG received
  ##  (ev_peer_cmd_pong or ev_client_cmd_pong intended for us)
}

## Handlers should relay, pong, or reset ping status appropriately.
sub irc_ev_peer_cmd_ping {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

}

sub irc_ev_peer_cmd_pong {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

}

sub irc_ev_client_cmd_ping {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

}

sub irc_ev_client_cmd_pong {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

}

1;
