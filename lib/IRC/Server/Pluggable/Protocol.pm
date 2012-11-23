package IRC::Server::Pluggable::Protocol;
our $VERSION = '0.000_01';

## Extends Protocol::Base by consuming various Protocol::Roles.
## (Consuming the base set of Roles should form a workable IRCD.)

use 5.12.1;
use strictures 1;

sub PROTO_ROLE_PREFIX () {
  'IRC::Server::Pluggable::Protocol::Role::TS::'
}

my @base_roles = map { PROTO_ROLE_PREFIX . $_ } qw/
  Register

  Clients
  Peers

  Channels
/;


use Moo;
use namespace::clean -except => 'meta';


extends 'IRC::Server::Pluggable::Protocol::Base';
with @base_roles;


no warnings 'void';
q{
<Gilded> I'm only level 24 myself so I try to avoid the hard quests
 like "Job" or "Sex"
};

=pod

=cut
