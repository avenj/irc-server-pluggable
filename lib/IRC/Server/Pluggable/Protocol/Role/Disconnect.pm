package IRC::Server::Pluggable::Protocol::Role::Disconnect;

## Provides:
##  ->disconnect()
## Handles:
##   - cmd_from_client_quit
##   - cmd_from_peer_quit
##   - cmd_from_unknown_quit

use 5.12.1;
use Carp;

use Moo::Role;
use strictures 1;

requires qw/
  users
  peers
  send_to_routes
/;

use Scalar::Util 'blessed';

## Types returned by _r_disconnect_get_target_type($target)
## Used to determine what disconnect() was called on
use constant {
  LOCAL_USER      => 1,
  LOCAL_PEER      => 2,
  REMOTE_USER     => 3,
  REMOTE_PEER     => 4,
  LOCAL_USER_CONN => 5,
  LOCAL_PEER_CONN => 6,
  UNKNOWN_CONN    => 7,
};


use namespace::clean -except => 'meta';


sub cmd_from_unknown_quit {
  my ($self, $conn) = @_;
  $self->disconnect( $conn,
    type => 'error',
    msg  => 'Client Quit',
  );
}

sub cmd_from_peer_quit {

}

sub cmd_from_client_quit {

}


sub _r_disconnect_get_target_type {
  my ($self, $target) = @_;

  my ($target_type, $route_id);

  TARGET: {
    ## See what kind of target we were passed.
    ## Set $route_id appropriately
    ## Set $target_type to one of these constants:
    ##   LOCAL_USER
    ##   LOCAL_PEER
    ##   REMOTE_USER
    ##   REMOTE_PEER
    ##   LOCAL_USER_CONN
    ##   LOCAL_PEER_CONN
    ##   UNKNOWN_CONN

    if (blessed $target
      && $target->isa('IRC::Server::Pluggable::IRC::User') ) {

      $target_type = $target->has_conn ? LOCAL_USER : REMOTE_USER ;
      $route_id    = $target->route;

      last TARGET
    }

    if (blessed $target
      && $target->isa('IRC::Server::Pluggable::IRC::Peer') ) {

      $target_type = $target->has_conn ? LOCAL_PEER : REMOTE_PEER ;
      $route_id    = $target->route;

      last TARGET
    }

    if (blessed $target
      && $target->isa('IRC::Server::Pluggable::Backend::Connect') ) {

      $target_type = $target->is_client ? LOCAL_USER_CONN
                     : $target->is_peer ? LOCAL_PEER_CONN
                     : UNKNOWN_CONN ;
      $route_id    = $target->wheel_id;

      last TARGET
    }

    confess "Could not determine type of target $target"

  } # TARGET

  wantarray ? ($target_type, $route_id) : $target_type
}

sub _r_disconnect_with_error {
  my ($self, $conn, $msg) = @_;

  ## Send ERROR and drop the Connect
  ## These only go to locals.
  ## disconnect() calls needed cleanup routines.

  $self->send_to_routes(
    {
      command => 'ERROR',
      params  => [ "Closing Link: ". $conn->peeraddr . " ($msg)" ],
    },
    $conn
  );

  $self->_r_disconnect_from_backend($conn);
}

sub _r_disconnect_from_backend {
  my ($self, $conn, $msg) = @_;

  ## Backend handles these after a socket flush.
  $conn->is_disconnecting($msg || "Client disconnect");
}

sub _r_disconnect_user_cleanup {
  ## FIXME
  ## call channel cleanups for user if we ->can()
  ## (cleanup method should live in Channels role)
  ## remove from ->users if this is a local user
  ## remove from ->peers->by_name() for the user's peer if
  ##  this is a remote user
}

sub _r_disconnect_peer_cleanup {
  ## FIXME
  ## call channel cleanup routines for users lost
  ## (should live in Channels role)
  ## remove from ->peers
}

## FIXME methods for:
##  - relay local user quit to all peers
##  - relay remote user quit to all peers except src
##  - relay squit

sub _r_disconnect_quit_local_user {
  ##  FIXME
  ##  call _r_disconnect_with_error
  ##  relay quit
  ##  call channel cleanups
}

sub _r_disconnect_quit_local_peer {
  ## FIXME set is_disconnecting
  ##  relay squit
  ##  call channel cleanups for users
  ##  ...
}

sub _r_disconnect_quit_remote_user {
  ## FIXME clear User object, cleanup channels, relay QUIT
}

sub _r_disconnect_quit_remote_peer {
  ## FIXME relay squit, ...
}

sub disconnect {
  my ($self, $target, %params) = @_;

  ## ->disconnect( $target_obj,
  ##  type   => $type,  ## 'error', 'quit'
  ##  msg    => $disconnect_string,
  ## )

  confess "Expected a target object"
    unless defined $target and blessed $target;

  my $message     = $params{msg} // $params{message} // '';
  my $action_type = uc($params{type} // 'QUIT' );

  my ($target_type, $route_id)
    = $self->_r_disconnect_get_target_type( $target );

  ## FIXME 'kill' type instead of a remote user discon..?
  for ($action_type) {
    when ("ERROR") {
      my $conn;

      if ($target_type == LOCAL_USER || $target_type == LOCAL_PEER) {
        ## Try to retrieve Backend::Connect for a User or Peer:
        $conn = $target->conn;
      } else {
        ## ... elsewise we should've been passed a Backend::Connect
        ## (*_CONN types)
        $conn = $target;
      }

      ## We can't disconnect remotes with an ERROR; someone is an idiot:
      confess "error-type disconnect called but no Backend::Connect"
        unless blessed $conn
        and $conn->isa('IRC::Server::Pluggable::Backend::Connect');

      ## Send ERROR and call for a backend disconnect:
      $self->_r_disconnect_with_error( $conn,
        $message || "Unknown error from ".caller()
      );
    }

    when ("QUIT") {
      ## FIXME
      ##  - could be:
      ##    LOCAL_USER_CONN/LOCAL_PEER_CONN, convert to User/Peer objs
      ##     and change to appropriate type
      ##    LOCAL_USER  (discon, relay quit)
      ##    LOCAL_PEER  (discon, relay squit, quits?)
      ##    REMOTE_USER (send kill?)
      ##    REMOTE_PEER (send squit)
      QUIT: {

        if ($target_type == LOCAL_USER_CONN) {
          my $user = $self->users->by_id( $target->wheel_id ) || return;
          $self->_r_disconnect_quit_local_user( $user, $message );
          last QUIT
        }

        if ($target_type == LOCAL_PEER_CONN) {
          my $peer = $self->peers->by_id( $target->wheel_id ) || return;
          $self->_r_disconnect_quit_local_peer( $peer, $message );
          last QUIT
        }

        if ($target_type == LOCAL_USER) {
          $self->_r_disconnect_quit_local_user( $target, $message );
          last QUIT
        }

        if ($target_type == LOCAL_PEER) {
          $self->_r_disconnect_quit_local_peer( $target, $message );
          last QUIT
        }

        if ($target_type == REMOTE_PEER) {
          $self->_r_disconnect_quit_remote_peer( $target, $message );
          last QUIT
        }

        if ($target_type == REMOTE_USER) {
          $self->_r_disconnect_quit_remote_user( $target, $message );
          last QUIT
        }

      } # QUIT

    }

  }

  ## FIXME cleanup routines as-necessary, depending on what this is

}

1;
