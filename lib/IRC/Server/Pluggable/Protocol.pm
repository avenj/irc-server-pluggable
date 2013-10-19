package IRC::Server::Pluggable::Protocol;
use Defaults::Modern;

## Extends Protocol::Base by consuming various Protocol::Roles.
## (Consuming the base set of Roles should form a workable IRCD.)

define PROTO_ROLE_PREFIX = 'IRC::Server::Pluggable::Protocol::Role::TS::';

use Moo;
use namespace::clean;

my @base_roles = map { PROTO_ROLE_PREFIX . $_ } qw/
 ## FIXME
/;

extends 'IRC::Server::Pluggable::Protocol::Base';
with @base_roles;

1

=pod

=cut
