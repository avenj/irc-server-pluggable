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

  $self->r_nick_from_peer_$type($conn, $event, $peer)
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
  ##  do conflict resolution like _intro ?
}

sub r_nick_from_peer_intro {
  my ($self, $conn, $event, $peer) = @_;

  my $nick = $event->params->[0];
  if (my $user = $self->users->by_name($nick)) {
    return $self->r_nick_intro_conflicting($user, @_[1 .. $#_])   
  }

  my (undef, $hops, $ts, $modestr, $username, $hostname, $server, $gecos)
    = @{ $event->params };

  ## FIXME
}

sub r_nick_intro_conflicting {
  my ($self, $user, $conn, $event, $peer) = @_;

  my $nick = $event->params->[0];

  unless ($peer->type eq 'TS') {
    ## FIXME Not a TS peer; kill both.
    return
  }

  my (undef, $hops, $ts, $modestr, $username, $hostname, $server, $gecos)
    = @{ $event->params };

  my $old = $user->user .'@'. $user->host;
  my $new = $username   .'@'. $hostname;

  ## See doc/irc/ts3.txt:
  if ($old eq $new) {
    ## Hosts match and incoming is older. Ignore line.
    return if $ts < $user->ts;
    ## FIXME otherwise kill ours and propogate new
    ## FIXME method to send to all directly-linked except specified peer?
  } else {
    ## Hosts don't match.
    ## Ignore line if incoming TS is older than ours.
    return if $ts > $user->ts;
    ## FIXME otherwise kill ours and propogate new
  }
}

sub r_nick_change_conflicting {
  ## FIXME similar to r_nick_intro_conflicting
}

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



1;
