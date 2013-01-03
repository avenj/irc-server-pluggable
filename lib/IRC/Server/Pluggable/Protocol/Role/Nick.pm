package IRC::Server::Pluggable::Protocol::Role::Nick;

use strictures 1;
use Moo::Role;

use namespace::clean;

with 'IRC::Server::Pluggable::Role::Interface::IRCd';

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


sub cmd_from_peer_nick {
  my ($self, $conn, $event, $peer) = @_;

  unless (@{ $event->params }) {
    warn "Missing params in NICK from ".$peer->name;
    return
  }

  my $type;
  if (@{ $event->params } >= 2) {
    ## Nick change, :prefix NICK newnick  or  :prefix NICK newnick :<TS>
    my $type = 'change';
  } elsif (@{ $event->params } == 7) {
    ## Introduction:
    ##  NICK <nick> <hops> <ts> +<umode> <user> <host> <serv> :<gecos>
    my $type = 'intro';
  } else {
    ## Dunno.
    warn "Malformed params in NICK (introduction) from ".$peer->name;
    return
  }

  $self->r_nick_from_peer_$type($conn, $event, $peer);
}


sub r_nick_from_peer_change {
  my ($self, $conn, $event, $peer) = @_;

  my ($nick) = parse_user( $event->prefix );
  my $user   = $self->users->by_name($nick);
  unless ($user) {
    warn "Malformed NICK from peer; no such user $nick";
    return
  }

  ## FIXME
}

sub r_nick_from_peer_intro {
  my ($self, $conn, $event, $peer) = @_;

  my ($nick, $hops, $ts, $modestr, $username, $hostname, $server, $gecos)
    = @{ $event->params };

  ## FIXME
}


1;
