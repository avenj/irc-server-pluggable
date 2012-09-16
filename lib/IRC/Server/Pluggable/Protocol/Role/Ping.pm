package IRC::Server::Pluggable::Protocol::Role::Ping;

use strictures 1;
use Carp;
use Moo::Role;

use POE;

use namespace::clean -except => 'meta';

requires qw/
  config
  send_to_routes
/;

sub conn_is_idle {
  my ($self, $conn) = @_;
  return unless $conn->has_wheel;
  ## A connection is idle, per irc_ev_connection_idle in base class
  ## Might be unknown, user, or peer.

  if (!$conn->is_client && !$conn->is_peer) {
    ## FIXME
    ## If the conn is not registered yet:
    ##  took too long to register, disconnect with Connection timeout
  }

  if ($conn->ping_pending) {
    ## FIXME
    ## If the conn has a pending ping already:
    ##  exceeded round-trip time, Ping timeout
  }

  ## Send ping to conn
  $self->send_to_routes(
    {
      command => 'PING',
      params  => [ $self->config->server_name ],
    },
  );
  ## Set pending ping status
  $conn->ping_pending(1);

  ## FIXME
  ## Clear pending ping status if PONG received
  ##  (ev_peer_cmd_pong or ev_client_cmd_pong intended for us)
}

## Handlers should relay, pong, or reset ping status appropriately.

sub cmd_from_client_ping {
  my ($self, $conn, $event) = @_;


  ## check args
  ## check if we're relaying
  ##  check if target server exists
  ##  check if it's us
  ## send back PONG otherwise
  unless (@{$event->params}) {
    $self->send_to_routes(
      $
    );
  }

}

sub cmd_from_client_pong {
  my ($self, $conn, $event) = @_;

  ## FIXME see if we're relaying similar to PING
}

sub cmd_from_peer_ping {
  ## see if we're relaying to another peer
  ## see if we're relaying from another peer to a local user
  ## send our own PONG,
}


sub cmd_from_peer_pong {
  my ($self, $conn, $event) = @_;

  ## FIXME see if we're relaying

}

1;
