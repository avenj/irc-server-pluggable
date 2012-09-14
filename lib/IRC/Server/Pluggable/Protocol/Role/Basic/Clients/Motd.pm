package IRC::Server::Pluggable::Protocol::Role::Basic::Clients::Motd;

use Moo::Role;
use strictures 1;


use namespace::clean -except => 'meta';


sub cmd_from_client_motd {
  my ($self, $conn, $event) = @_;

  ## FIXME
  ##  Retrieve MOTD from $self->config
  ##  send_to_routes
}

1;
