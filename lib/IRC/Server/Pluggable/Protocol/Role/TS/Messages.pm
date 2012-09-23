package IRC::Server::Pluggable::Protocol::Role::TS::Messages;

use Moo::Role;
use strictures 1;

use IRC::Server::Pluggable qw/
  IRC::EventSet
/;

use Scalar::Util 'blessed';

use namespace::clean -except => 'meta';

### Basic message relay rules:
## One-to-one:
##  * User to local user
##    - Relay locally
##  * User to remote user
##    - Relay to next-hop peer in this user's path
##      ( ->route() )
## One-to-many:
##  * User to channel
##   - Relay to own users
##   - Accumulate route() IDs for users on channel,
##     relay to each unique route()

### Errors:

requires qw/
  config
  channels
  channel_types
  peers
  users
  send_to_routes
/;

## FIXME also see _state_parse_msg_targets in PCSI
##  + cmd_message / peer_message
## some helpful pointers.

sub _r_msgs_accumulate_targets_channel {
  ## Accumulate a list of route IDs for a channel target
  ## including routes to applicable local users
  my ($self, $chan_name) = @_;

  unless (blessed $chan) {
    $chan = $self->channels->by_name($chan);
  }

  ## Should never be called for nonexistant chans:
  confess "Expected an IRC::Channel but got $chan"
    unless blessed $chan
    and $chan->isa('IRC::Server:Pluggable::IRC::Channel');

  my %routes;
  for my $nick (@{ $chan_obj->nicknames_as_array }) {
    my $user  = $self->users->by_name($nick);
    $routes{ $user->route() } ||= 1;
  }

  my @routes = keys %routes;
  wantarray ? @routes : \@routes
}

sub _r_msgs_accumulate_targets_servermask {
  ## $$mask targets
  my ($self, $mask) = @_;
  my @peers = $self->peers->matching($mask);

  my %routes;
  for my $peer (@peers) {
    $routes{ $peer->route() } ||= 1;
  }

  my @routes = keys %routes;
  wantarray ? @routes : \@routes
}

sub _r_msgs_accumulate_targets_hostmask {
  ## $#mask targets
  my ($self, $mask) = @_;
  my @users = $self->users->nuh_matching($mask);

  my %routes;
  for my $user (@users) {
    $routes{ $user->route() } ||= 1;
  }

  my @routes = keys %routes;
  wantarray ? @routes : \@routes
}

sub _r_msgs_accumulate_targets_statustype {
  ## Status-prefixed targets, ie. @#channel-like targets

}


sub _r_msgs_can_send_to_nick {

}

sub _r_msgs_can_send {
  ## FIXME
  ##  For a channel, Role::Channels provides user_can_send_to_chan
  ##  Should we provide user_can_send_to_user ?
}

sub _r_msgs_parse_targets {
  my ($self, @targets) = @_;
  ## Borrowed from POE::Component::Server::IRC's target parser,
  ## which is reasonably clever.
  ## Turns a list of targets into a hash:
  ##  $target => [ $type, @args ]
  ## Valid types:
  ##   channel
  ##   channel_prefixed
  ##   servermask
  ##   hostmask
  ##   nick
  ##   nick_fully_qualified

  my @chan_prefixes = keys %{ $self->channel_types };
  ## FIXME where do we set/get status prefixes...?

  my %targets;

  TARGET: for my $target (@targets) {

    my $t_prefix = substr($target, 0, 1);
    for my $prefix (@chan_prefixes) {
      if ($t_prefix eq $prefix) {
        $targets{$target} = [ 'channel' ];
        next TARGET
      }
    }

    ## FIXME similar to above but check for valid status prefixes

    ##   preceeding valid chan prefixes, preserve both as args
    if ($target =~ /^\${2}(.+)$/) {
      ## Server mask - $$mask
      $targets{$target} = [ 'servermask', $1 ];
      next TARGET
    }

    if ($target =~ /^\$\#(.+)$/) {
      ## Host mask - $#mask
      $targets{$target} = [ 'hostmask', $1 ];
      next TARGET
    }

    if ($target =~ /@/) {
      ## nick@server
      my ($nick, $server) = split /@/, $target, 2;
      my $host;
      ($nick, $host) = split /%/, $nick, 2 if $nick =~ /%/;
      $targets{$target} = [
        'nick_fully_qualified',
        $nick, $server, $host
      ];
      next TARGET
    }

    ## Fall through to nickname
    $targets{$target} = [ 'nick' ];
  } ## TARGET


  \%targets
}

sub handle_message_relay {
  ## handle_message_relay(
  ##  prefix   => $nick,
  ##  src_conn => $conn,
  ##  string   => $string,
  ##  targets  => [ @targets ],
  ##  type     => $type,
  ## FIXME do we need anything else ?
  ## )
  my ($self, %params) = @_;

  for my $req (qw/prefix src_conn string targets type/) {
    confess "missing argument '$req =>'";
      unless defined $params{$req};
  }

  my $eventset = IRC::Server::Pluggable::IRC::EventSet->new;

  ## FIXME
  ##  Parse targets
  ##  Call handlers as-needed
  ##  Accumulate EventSet
  my $target_array = ref $params{targets} eq 'ARRAY' ?
    $params{targets} : [ $params{targets} ];

  my $tcount;
  my $targetset = $self->_r_msgs_parse_targets(@$target_array);
  DEST: for my $target (keys %$targetset) {
    my ($t_type, @t_params) = @{ $targetset->{$target} };
    ## FIXME sanity checks, build EventSet if we hit errors
    ##  - 481 if prefix nick not an oper and target is host/servermask
    ##  - 413 if target is a mask and doesn't contain a .
    ##  - 414 if target is a mask and doesn't look like a mask?
    ##     pcsi uses !~ /\x2E.*[\x2A\x3F]+.*$/
    ##  - 401 if channel / nick doesn't exist
    ##  - 402 if nick_fully_qualified and peer doesn't exist
    ##  - incr target count and 407 if we're over max targets
    ## FIXME call appropriate methods to accumulate routes as-needed
    ##  pcsi uses some funkyness in dispatching send_output ...
    ## FIXME sort out full/nickname prefix situation

    ## Organized vaguely by usage frequency ...

    $tcount++;
    ## FIXME 407 + last if $tcount > maxtargets

   ## FIXME always delete originator, ie. src_conn->wheel_id

    for ($t_type) {
      when ("channel") {
        ## - 401 if channel nonexistant
        unless (my $chan = $self->channels->by_name($t_params[0])) {
          $eventset->push(
            $self->numeric->to_hash( 401,
              prefix => $self->config->server_name,
              params => [ $target ],
              target => $params{prefix},
            )
          );
          next DEST
        }
        ## - call _r_msgs_accumulate_targets_channel to get routes
        my %routes = $self->_r_msgs_accumulate_targets_channel($chan);
        ## - delete originator ($params{src_conn}->wheel_id)
        delete $routes{ $params{src_conn}->wheel_id() };
        ## FIXME
        ## - find out if this user can send
      }

      when ("nick") {
        my $user;
        unless ($user = $self->users->by_name($t_params[0])) {
          $eventset->push(
            $self->numeric->to_hash( 401,
              prefix => $self->config->server_name,
              params => [ $target ],
              target => $params{prefix},
            );
          );
          next DEST
        }
        ## FIXME
      }

      when ("nick_fully_qualified") {
      }

      when ("channel_prefixed") {
      }

      when ("servermask") {
      }

      when ("hostmask") {
      }
    }
  } ## DEST
}

sub cmd_from_client_privmsg {
  my ($self, $conn, $ev, $user) = @_;

  $self->handle_message_relay(
    type     => 'privmsg',
    src_conn => $conn,
    prefix   => $user->nick,
    targets  => FIXME get params
  );
}

sub cmd_from_client_notice {}

sub cmd_from_peer_privmsg {}
sub cmd_from_peer_notice {}


1;
