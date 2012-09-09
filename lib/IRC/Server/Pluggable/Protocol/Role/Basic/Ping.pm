package IRC::Server::Pluggable::Protocol::Role::Basic::Ping;

use strictures 1;
use Carp;
use Moo::Role;

use POE;

use namespace::clean -except => 'meta';

requires qw/
  send_to_routes
/;

sub conn_is_idle {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## A connection is idle, per irc_ev_connection_idle in base class
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

sub cmd_from_client_ping {}
sub cmd_from_client_pong {}

sub cmd_from_peer_ping {}
sub cmd_from_peer_pong {}

1;
