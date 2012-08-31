package IRC::Server::Pluggable::Role::Clients;

## This Role should only consume other roles.
## It should not define things itself.

use strictures 1;
use Moo::Role;

sub ROLES () {
  'IRC::Server::Pluggable::Protocol::Role::Clients::'
}

with ROLES . 'Register';



1;
