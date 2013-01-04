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

  ## hopcount++
  $event->params->[1]++;
  ## FIXME intro user and relay to list_local_peers
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

  $event->params->[1]++;
  if ($ts < $user->ts) {
    ## Received TS lower than existing TS.
    ## Collide new if u@h match, otherwise collide existing.
    if ($user->user eq $username && $user->host eq $hostname) {
      $collided = $nick
    } else {
      $collided = $user->id
    }
  } elsif ($ts > $user->ts) {
    ## Received TS higher than existing TS.
    ## Collided existing if u@h match, otherwise collide new.
    if ($user->user eq $username && $user->host eq $hostname) {
      $collided = $user->id
    } else {
      $collided = $nick
    }
  } else {
    ## TS are equal, collide both.
    ## FIXME
  }

  ## FIXME see ts6-v8.txt 'Nick TS collisions'
  $self->disconnect(
    target => $collided,
    type   => 'kill',
    ## FIXME
    msg    => 'Nickname collision',
  );

  ## FIXME propogate NICK 
  $self->send_to_local_peers( $event,
    except => $peer
  );
}

sub r_nick_change_conflicting {
  ## FIXME similar to r_nick_intro_conflicting
}

## Different u@h:
##  - incoming_TS < existing_TS == kill existing
## Same u@h:
##  - incoming_TS < ex

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
