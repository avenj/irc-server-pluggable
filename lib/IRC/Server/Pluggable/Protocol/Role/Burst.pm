package IRC::Server::Pluggable::Protocol::Role::Burst;

use Carp;
use Moo::Role;
use strictures 1;

use namespace::clean -except => 'meta';

requires qw/
  send_to_routes
/;

## FIXME
##  Sync-related methods
##  Possible that this should be logic-only and Protocol action should
##   maybe take place in Clients/Peers::Sync roles or so?
## Not sure.
## Simple method(s) that take action, timestamp, and args and dispatch
## internally to get a standardized set of pass/bounce/ignore
## specification back may make sense

1;
