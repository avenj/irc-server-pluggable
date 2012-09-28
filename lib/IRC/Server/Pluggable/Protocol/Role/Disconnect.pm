package IRC::Server::Pluggable::Protocol::Role::Disconnect;

use 5.12.1;
use Carp;

use Moo::Role;
use strictures 1;

requires qw/
  send_to_routes
/;

use Scalar::Util 'blessed';

## FIXME Should we define a disconnected event handler
##  in ::Base and add 'around's that call $orig where we need to?
##  Maybe better to just have a single handler that dispatches out to
##  role methods that handle channel/user/peer cleanup.

sub _r_disconnect_get_target_type {
  my ($self, $target) = @_;

  my ($target_type, $route_id);

  TARGET: {
    ## See what kind of target we were passed.
    ## Set $route_id appropriately
    ## Set $target_type to one of:
    ##   local_user
    ##   local_peer
    ##   remote_user
    ##   remote_peer
    ##   local_user_conn
    ##   local_peer_conn
    ##   unknown_conn

    if (blessed $target
      && $target->isa('IRC::Server::Pluggable::IRC::User') ) {

      $target_type = $target->has_conn ? 'local_user' : 'remote_user' ;
      $route_id    = $target->route;

      last TARGET
    }

    if (blessed $target
      && $target->isa('IRC::Server::Pluggable::IRC::Peer') ) {

      $target_type = $target->has_conn ? 'local_peer' : 'remote_peer' ;
      $route_id    = $target->route;

      last TARGET
    }

    if (blessed $target
      && $target->isa('IRC::Server::Pluggable::Backend::Connect') ) {

      $target_type = $target->is_client ? 'local_user_conn'
                     : $target->is_peer ? 'local_peer_conn'
                     : 'unknown_conn' ;
      $route_id    = $target->wheel_id;

      last TARGET
    }

    confess "Could not determine type of target $target"

  } # TARGET

  wantarray ? ($target_type, $route_id) : $target_type
}

sub _r_disconnect_with_error {
  my ($self, $conn, $msg) = @_;

  ## These only go to locals.

  $self->send_to_routes(
    {
      command => 'ERROR',
      params  => [ "Closing Link: ". $conn->peeraddr . " ($msg)" ],
    },
    $conn
  );

  $self->_r_disconnect_from_backend($conn);
}

sub _r_disconnect_client_quit {
  ## FIXME
}

sub _r_disconnect_from_backend {
  my ($self, $conn, $msg) = @_;

  ## Backend handles these after a socket flush.
  $conn->is_disconnecting($msg || "Client disconnect");
}

sub _r_disconnect_user_cleanup {
  ## FIXME call channel cleanups for user
  ## (should live in Channels role)
}

sub _r_disconnect_peer_cleanup {
  ## FIXME call channel cleanup routines for lost peer
  ## (should live in Channels role)
}

sub disconnect {
  my ($self, %params) = @_;

  ## ->disconnect(
  ##  target => $obj,
  ##  type   => $type,  ## 'error', 'quit'
  ##  msg    => $disconnect_string,
  ## )

  my $target = $params{target}
    // confess "missing required param 'target =>'";

  my $message     = $params{msg} // $params{message} // '';
  my $action_type = uc($params{type} // 'QUIT' );

  my ($target_type, $route_id)
    = $self->_r_disconnect_get_target_type( $target );

  for ($action_type) {
    when ("ERROR") {
      my $conn;

      if ($target_type eq 'local_user' || $target_type eq 'local_peer') {
        ## Try to retrieve Backend::Connect for a User or Peer:
        $conn = $target->conn;
      } else {
        $conn = $target;
      }

      ## We can't disconnect remotes with an ERROR.
      confess "error-type disconnect called but no Backend::Connect"
        unless blessed $conn
        and $conn->isa('IRC::Server::Pluggable::Backend::Connect');

      $self->_r_disconnect_with_error($conn, $message);
      ## FIXME cleanup routines
    }

    when ("QUIT") {
      ## FIXME
    }
  }
}


## FIXME
##  Provide a generic proxy method for various disconnect types
##  hybrid basically does this.
## Backend lets us set a disconnect string in is_disconnecting()

1;
