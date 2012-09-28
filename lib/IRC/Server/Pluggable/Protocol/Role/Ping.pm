package IRC::Server::Pluggable::Protocol::Role::Ping;

use strictures 1;
use Carp;
use Moo::Role;

use namespace::clean -except => 'meta';

requires qw/
  config
  disconnect
  numeric
  send_to_routes
  users
/;

sub conn_is_idle {
  my ($self, $conn) = @_;
  return unless $conn->has_wheel;
  ## A connection is idle, per irc_ev_connection_idle
  ## Might be unknown, user, or peer.

  if (!$conn->is_client && !$conn->is_peer) {
    ## Took too long to register.
    $self->disconnect(
      type   => 'error',
      target => $conn,
      msg    => 'Connection timeout',
    );
    ## FIXME do we need to tell register bits to clean up?
    ##  should probably issue disconnect events and catch
    ##  to drop pending registrations
  }

  if ($conn->ping_pending) {
    ## Exceeded round-trip time.
    ## Call for a disconnect.
    $self->disconnect(
      type   => 'quit',
      target => $conn,
      msg    => 'Ping timeout',
    );
  }

  ## Send ping to conn
  $self->send_to_routes(
    {
      command => 'PING',
      params  => [ $self->config->server_name ],
    },
    $conn
  );

  ## Set pending ping status
  $conn->ping_pending(1);
}

## Handlers should relay, pong, or reset ping status appropriately.

sub cmd_from_client_ping {
  my ($self, $conn, $event, $user) = @_;

  my $server_name = $self->config->server_name;

  unless (@{$event->params}) {
    $self->send_to_routes(
      $self->numeric->as_hash( 409,
        target => $user->nick,
        prefix => $server_name,
        params => [ 'PING' ],
      ),
      $conn
    );
    return
  }

  my ($ping_param, $target_peer) = @{ $event->params };

  if (defined $target_peer && uc($target_peer) ne uc($server_name) ) {
    ## Target specified (and it's not us)
    my $peer = $self->peers->by_name($target_peer);

    if (! defined $peer) {
      ## Nonexistant target.
      $self->send_to_routes(
        $self->numeric->as_hash( 402,
          target => $user->nick,
          prefix => $server_name,
          params => [ $target_peer ],
        ),
        $conn
      );
      return
    } else {
      ## Relay PING to target peer.
      $self->send_to_routes(
        {
          command => 'PING',
          params  => [ $user->nick, $peer->name ],
        },
        $peer
      );
      return
    }
  }

  ## No params; send PONG.
  $self->send_to_routes(
    {
      prefix  => $server_name,
      command => 'PONG',
      params  => [ $server_name, $ping_param ],
    },
    $conn
  );
}

sub cmd_from_client_pong {
  my ($self, $conn, $event, $user) = @_;

  my $server_name = $self->config->server_name;

  unless (@{$event->params}) {
    $self->send_to_routes(
      $self->numeric->as_hash( 409,
        target => $user->nick,
        prefix => $server_name,
        params => [ 'PING' ],
      ),
      $conn
    );
    return
  }

  my (undef, $target_peer) = @{ $event->params };

  if (defined $target_peer && uc($target_peer) ne uc($server_name)) {
    my $peer = $self->peers->by_name($target_peer);
    if (! defined $peer) {
      $self->send_to_routes(
        $self->numeric->as_hash( 402,
          target => $user->nick,
          prefix => $server_name,
          params => [ $target_peer ],
        ),
        $conn
      );
      return
    } else {
      $self->send_to_routes(
        {
          command => 'PONG',
          params  => [ $user->nick, $target_peer ],
        },
        $peer
      );
      return
    }
  }

  $conn->ping_pending(0);
}

sub cmd_from_peer_ping {
  my ($self, $conn, $event, $peer) = @_;
  return unless @{ $event->params };

  my $server_name = $self->config->server_name;

  my ($src, $target) = @{ $event->params };

  if (defined $target && uc($target) ne uc($server_name) ) {
    my $output = {
      command => 'PING',
      params  => $event->params,
    };

    if      (my $target_user = $self->users->by_name($target)) {
      return $self->send_to_routes( $output, $target_user->route )
    } elsif (my $target_peer = $self->peers->by_name($target)) {
      return $self->send_to_routes( $output, $target_peer->route )
    }
  }

  $self->send_to_routes(
    {
      command => 'PONG',
      params  => [ $server_name, $src ],
    },
    $conn
  );
}

sub cmd_from_peer_pong {
  my ($self, $conn, $event) = @_;
  return unless @{ $event->params };

  my $server_name = $self->config->server_name;

  my ($src, $target) = @{ $event->params };

  if (defined $target && uc($target) ne uc($server_name) ) {
    my $output = {
      command => 'PONG',
      params  => $event->params,
    };

    if      (my $target_user = $self->users->by_name($target)) {
      return $self->send_to_routes( $output, $target_user->route )
    } elsif (my $target_peer = $self->peers->by_name($target)) {
      return $self->send_to_routes( $output, $target_peer->route )
    }
  }

  $conn->ping_pending(0);
}

1;

=pod

=head1 NAME

IRC::Server::Pluggable::Protocol::Role::Ping

=head1 SYNOPSIS

Handles:

  conn_is_idle
  cmd_from_client_ping
  cmd_from_client_pong
  cmd_from_peer_ping
  cmd_from_peer_pong

=head1 DESCRIPTION

A Protocol::Role providing PING / PONG for clients & peers.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
