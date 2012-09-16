package IRC::Server::Pluggable::Protocol;
our $VERSION = 0;

## Extends Protocol::Base by consuming various Protocol::Roles.
## (Consuming the base set of Roles should form a workable IRCD.)

use 5.12.1;
use strictures 1;

use Moo;

use namespace::clean -except => 'meta';

extends 'IRC::Server::Pluggable::Protocol::Base';


### Roles, composed in order.
### (Base gives us Role::CaseMap and Protocol::Role::Send)

sub PROTO_ROLE_PREFIX () {
  'IRC::Server::Pluggable::Protocol::Role::Basic::'
}

with PROTO_ROLE_PREFIX . 'Messages' ;
with PROTO_ROLE_PREFIX . 'Register' ;
with PROTO_ROLE_PREFIX . 'Clients'  ;
with PROTO_ROLE_PREFIX . 'Peers'    ;
with PROTO_ROLE_PREFIX . 'Ping'     ;

no warnings 'void';
q{
<Gilded> I'm only level 24 myself so I try to avoid the hard quests
 like "Job" or "Sex"
};

=pod

=cut
