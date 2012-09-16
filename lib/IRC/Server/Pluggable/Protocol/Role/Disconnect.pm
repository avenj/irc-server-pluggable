package IRC::Server::Pluggable::Protocol::Role::Disconnect;

use Moo::Role;
use strictures 1;

requires qw/
  send_to_routes
/;

use Scalar::Util 'blessed';

sub disconnect {
  my ($self, $item, $str) = @_;

  TYPE: {
    if (blessed $item && $item->isa('IRC::Server::Pluggable::IRC::User')) {
      last TYPE
    }
    if (blessed $Item && $item->isa('IRC::Server::Pluggable::IRC::Peer')) {
      last TYPE
    }
    ## FIXME else a route id ?
  }


  ## FIXME do cleanup in Protocol
  ## FIXME call channel cleanups, etc
  ## FIXME tell dispatcher to tell backend to call a disconnect?
}

## FIXME
##  Provide a generic proxy method for various disconnect types
##  hybrid basically does this.
## Backend lets us set a disconnect string in is_disconnecting()

1;
