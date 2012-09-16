package IRC::Server::Pluggable::Protocol::Role::TS::Clients;

use strictures 1;
use Moo::Role;

sub PREFIX () { 'IRC::Server::Pluggable::Protocol::Role::TS::Clients::' }

use namespace::clean -except => 'meta';




## FIXME figure out 'core' user command bits that belong in Roles
##  Figure out modular or potentially reloadable bits that belong in Plugins

1;
