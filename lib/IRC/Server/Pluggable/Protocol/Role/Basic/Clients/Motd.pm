package IRC::Server::Pluggable::Protocol::Role::Basic::Clients::Motd;

use Moo::Role;
use strictures 1;


use namespace::clean -except => 'meta';


sub cmd_from_client_motd {
  my ($self, $conn, $event) = @_;

  my @motd = $self->config->has_motd ?
              @{ $self->config->motd }
              : () ;

  my $target_nick = $event->prefix;
  my $target_user = $self->users->by_name($target_nick);

  ## FIXME 422 if no motd

  ## FIXME send a 375 intro line

  for my $line (@motd) {
    ## FIXME send a 372 with "- $line" for each line
  }

  ## FIXME send a 376 end-of-motd

  1
}

1;
