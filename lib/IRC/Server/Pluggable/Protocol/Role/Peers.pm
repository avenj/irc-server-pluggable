package IRC::Server::Pluggable::Protocol::Role::Peers;

## FIXME split out

use strictures 1;
use Moo::Role;

use POE;

use namespace::clean;


sub cmd_from_peer_nick {
  ## FIXME
  ## maybe this should be in Register.pm?
  ## TS3 NICK rules.
  ## nick-change:
  ##  :oldnick NICK newnick :<TS>
  ## new-nick:
  ##  NICK <NICK> <HOPS> <TS> +<UMODE> <USER> <HOST> <SERV> :<GECOS>
  ## CONFLICTS:
  ## if from non-TS peer:
  ##  - kill both
  ## different user@hosts:
  ##  - if ts() are equal kill both if it was a nick change
  ##  - if incoming TS is older, kill ours, relay new
  ##  - if incoming TS is newer, ignore, kill old if nick change
  ## same user@host:
  ##  - if ts() are equal kill both if it was a nick change
  ##  - if the incoming TS is older, ignore, kill old if nick change
  ##  - if the incoming TS is newer, kill ours, relay new
}

sub cmd_from_peer_server {
  ## Peer introducing server.
  my ($self, $conn, $event) = @_;

  my $intro_by = $event->prefix;
  my ($new_peer_name, $hop_count, $gecos_str) = @{ $event->params };

  ## FIXME
  ##  ... ->can() hooks for leaf/hub verification etc?
  ##  Create a Peer obj for this w/ route() set to our intro_by route()
}


sub cmd_from_peer_squit {

}



1;
