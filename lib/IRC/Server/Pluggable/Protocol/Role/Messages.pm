package IRC::Server::Pluggable::Protocol::Role::TS::Messages;

use 5.12.1;
use strictures 1;

use Carp;
use Moo::Role;

use IRC::Server::Pluggable qw/
  Constants

  IRC::EventSet

  Utils
/;

use Scalar::Util 'blessed';

use namespace::clean -except => 'meta';

## FIXME hum, *very* possible this should move to Role::Messages

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
  process
  users
  user_cannot_send_to_chan
  send_to_routes
/;


sub cmd_from_client_privmsg {
  my ($self, $conn, $ev, $user) = @_;

  $self->handle_message_relay(
    type     => 'privmsg',
    src_conn => $conn,
    prefix   => $user->nick,
    targets  => '',## FIXME get params
  );
}

sub cmd_from_client_notice {}

sub cmd_from_peer_privmsg {}
sub cmd_from_peer_notice {}

sub handle_message_relay {
  ## handle_message_relay(
  ##  prefix   => $nick,
  ##  src_conn => $conn,
  ##  string   => $string,
  ##  targets  => [ @targets ],
  ##  type     => $type,
  ## )
  my ($self, %params) = @_;

  for my $req (qw/prefix src_conn string targets type/) {
    confess "missing required argument $req"
      unless defined $params{$req}
  }

  $params{type} = lc $params{type};

  unless (blessed $params{src_conn} &&
      $params{src_conn}->isa('IRC::Server::Pluggable::Backend::Connect')) {
    confess "Cannot handle_message_relay;",
      "Expected 'src_conn' to be an IRC::Server::Pluggable::Backend::Connect"
    ## FIXME handle src eq spoofed?
  }

  my $target_array = ref $params{targets} eq 'ARRAY' ?
    $params{targets} : [ $params{targets} ];

  my ($targetset, $err_set) = $self->r_msgs_parse_targets(@$target_array);

  my $max_msg_targets = $self->config->max_msg_targets;

  ## May or may not have a source User obj for originator:
  my ($parsed_prefix) = parse_user($params{prefix});
  my $user_obj = $self->users->by_name($parsed_prefix);

  my $tcount;
  DEST: for my $target (keys %$targetset) {
    my ($t_type, @t_params) = @{ $targetset->{$target} };
    ## FIXME
    ##  - 413 if target is a mask and doesn't contain a .
    ##  - 414 if target is a mask and doesn't look like a mask?
    ##     pcsi uses !~ /\x2E.*[\x2A\x3F]+.*$/

    ## Organized vaguely by usage frequency ...

    if (++$tcount > $max_msg_targets) {
      $err_set->push(
        $self->numeric->to_hash( 407,
          prefix => $self->config->server_name,
          params => [ $target ],
          target => $parsed_prefix,
        )
      );
      last DEST
    }

    ## FIXME always delete originator, ie. src_conn->wheel_id from routes

    for ($t_type) {

      ## Message to channel, simple.
      when ('channel') {
        my $chan;
        unless ($chan = $self->channels->by_name($t_params[0])) {
          ## No such channel (401)
          $err_set->push(
            $self->numeric->to_hash( 401,
              prefix => $self->config->server_name,
              params => [ $target ],
              target => $parsed_prefix,
            )
          );
          next DEST
        }

        my %routes = $self->r_msgs_accumulate_targets_channel($chan);

        ## If we don't have a user_obj, it's likely safe to assume that
        ## this is a spoofed message-from-server or suchlike.
        ## If we do, see if they can send.
        if (defined $user_obj &&
          (my $err = $self->user_cannot_send_to_chan($user_obj, $target)) ) {
          $err_set->push($err);
          next DEST
        }

        my %out = (
          command => $params{type},
          params  => [ $target, $params{string} ],
        );

        delete $routes{ $params{src_conn}->wheel_id() };
        ## FIXME Document preprocessing hooks
        ##  Could be used to support IRCv3 intent translation f.ex
        ##  (P_message_* handlers doing their own relay & EAT_CLIENT)
        next DEST if $self->process( 'message_to_chanmember',
            \%out,
            $target,
            \%routes
        ) == EAT_ALL;

        for my $id (keys %routes) {
          my $route_type = $self->r_msgs_get_route_type($id) || next;
          my $src_prefix =
            $self->r_msgs_gen_prefix_for_type($route_type, $user_obj)
            || $params{prefix};

          my $ref = { prefix => $src_prefix, %out };

          $self->send_to_routes($ref, $id);
        }
      }

      ## Message to nickname.
      when ('nick') {
        my $user;
        unless ($user = $self->users->by_name($t_params[0])) {
          $err_set->push(
            $self->numeric->to_hash( 401,
              prefix => $self->config->server_name,
              params => [ $target ],
              target => $parsed_prefix,
            )
          );
          next DEST
        }

        ## FIXME check for cannot_send

        my $src_prefix = $user->has_conn ? $user->full : $user->nick ;
        my $ref = {
          prefix  => $src_prefix,
          command => $params{type},
          params  => [ $target, $params{string} ],
        };

        next DEST if $self->process( 'message_to_user',
          $ref,
          $target,
          $user
        ) == EAT_ALL;

        $self->send_to_routes( $ref, $user->route )
      }


      ## Message to nick@server or nick%host@server
      when ('nick_fully_qualified') {
        my ($nick, $server, $host) = @t_params;
        my $user;
        unless ($user = $self->users->by_name($nick)) {
          $err_set->push(
            $self->numeric->to_hash( 401,
              prefix => $self->config->server_name,
              params => [ $target ],
              target => $parsed_prefix,
            )
          );
          next DEST
        }

        if (defined $host && lc($host) ne lc($user->host) ) {
          ## May or may not have a host.
          ## If we do and this user isn't a match, 401:
          $err_set->push(
            $self->numeric->to_hash( 401,
              prefix => $self->config->server_name,
              params => [ $target ],
              target => $parsed_prefix,
            )
          );
          next DEST
        }

        my $peer;
        ## Might be us, might be remote.
        unless (lc($server) eq lc($self->config->server_name) ||
             ($peer = $self->peers->by_name($server)) ) {
          $err_set->push(
            $self->numeric->to_hash( 402,
              prefix => $self->config->server_name,
              params => [ $server ],
              target => $parsed_prefix,
            )
          );
          next DEST
        }
        ## FIXME check cannot_send_to_user only if local...?
        ##  Relay to peer if not us
      }


      ## Message to prefixed channel (e.g. @#channel)
      when ('channel_prefixed') {
        my ($channel, $status_prefix) = @t_params;

        my $chan_obj;

        unless ($chan_obj = $self->channels->by_name($channel)) {
          $err_set->push(
            $self->numeric->to_hash( 401,
              prefix => $self->config->server_name,
              params => [ $channel ],
              target => $parsed_prefix,
            )
          );
          next DEST
        }

        my %routes = $self->r_msgs_accumulate_targets_statustype(
          $status_prefix,
          $chan_obj
        );
        delete $routes{ $params{src_conn}->wheel_id() };
        ## FIXME
        ## FIXME what're the can-send rules here ...?
      }


      ## Message to $$servermask
      when ('servermask') {
        ## FIXME add relevant local users if we match also
        ## FIXME 481 if not an oper
      }


      ## Message to $#hostmask
      when ('hostmask') {
        ## FIXME 481 if not an oper
      }
    }
  } ## DEST

  ## Notices should return no error at all
  ##  see http://tools.ietf.org/html/rfc2812#section-3.3
  if ($err_set->has_events && $params{type} ne 'notice') {
    $self->send_to_routes( $err_set, $params{src_conn}->wheel_id )
  }
  ## FIXME hooks for events to spoofed clients?
}


sub user_cannot_send_to_user {
  ## FIXME
  ##  User-to-user counterpart to Channels->user_cannot_send_to_chan
}


sub r_msgs_get_route_type {
  my ($self, $route_id) = @_;
  ## FIXME this should move to a more generalized role ...
  ## Determine a remote route's type given just an ID.
  ## If we have a user_obj to work with, determine a prefix, also.

  my $route_type;
  if (my $user = $self->users->by_id($route_id)) {
    $route_type = 'user';
  } elsif (my $peer = $self->peers->by_id($route_id)) {
    $route_type = 'peer';
  } else {
    carp "r_msgs_get_route_type cannot find ID $route_id";
    return
  }

  $route_type
}

sub r_msgs_gen_prefix_for_type {
  my ($self, $route_type, $user_obj) = @_;

  if (defined $user_obj) {
    return $route_type eq 'user' ? $user_obj->full : $user_obj->nick
  }

  return
}

sub r_msgs_accumulate_targets_channel {
  ## Accumulate a list of route IDs for a channel target
  ## including routes to applicable local users
  my ($self, $chan) = @_;

  unless (blessed $chan) {
    $chan = $self->channels->by_name($chan);
  }

  ## Should never be called for nonexistant chans:
  confess "Expected an IRC::Channel but got $chan"
    unless blessed $chan
    and $chan->isa('IRC::Server:Pluggable::IRC::Channel');

  my %routes;
  for my $nick (@{ $chan->nicknames_as_array }) {
    my $user  = $self->users->by_name($nick);
    ## An override would want to skip deaf users here, etc.
    $routes{ $user->route() }++
  }

  %routes
}

sub r_msgs_accumulate_targets_servermask {
  ## $$mask targets
  my ($self, $mask) = @_;
  my @peers = $self->peers->matching($mask);

  my %routes;
  for my $peer (@peers) {
    $routes{ $peer->route() }++
  }

  %routes
}

sub r_msgs_accumulate_targets_hostmask {
  ## $#mask targets
  my ($self, $mask) = @_;
  my @users = $self->users->nuh_matching($mask);

  my %routes;
  for my $user (@users) {
    $routes{ $user->route() }++;
  }

  %routes
}


sub r_msgs_accumulate_targets_statustype {
  ## Status-prefixed targets, ie. @#channel-like targets
  my ($self, $status, $chan_obj) = @_;

  my $mode = $self->channels->status_mode_for_prefix($status);
  unless ($mode) {
    carp "Cannot accumulate targets; ",
     "no mode for status prefix $status available for $chan_obj";
    return
  }

  my %routes;
  for my $user ($chan_obj->nicknames_as_array) {
    $routes{ $user->route() }++
      if $chan_obj->user_has_mode($user->nick, $mode)
  }

  %routes
}

sub r_msgs_parse_targets {
  my ($self, @targets) = @_;
  ## Concept borrowed from POE::Component::Server::IRC's target parser,
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

  my @chan_prefixes   = keys %{ $self->channel_types };
  my @status_prefixes = $self->channels->available_status_modes;

  my %targets;

  my $err_set = IRC::Server::Pluggable::IRC::EventSet->new;

  TARGET: for my $target (@targets) {

    my $t_prefix = substr($target, 0, 1);
 
    if (grep {; $t_prefix eq $_ } @chan_prefixes) {
      ## Message to channel target.
      $targets{$target} = [ 'channel' ];
      next TARGET
    }
 
    if (grep {; $t_prefix eq $_ } @status_prefixes) {
      ## Message to status target.
      my $c_prefix = substr($target, 1, 1);
      unless (grep { $c_prefix eq $_ } @chan_prefixes) {
        ## FIXME @ prefix but not a channel?
        ## Not sure of any IRCDs with syntax along those lines ...
        ## ... add error hash ?
      }
      ## Change target to bare channel name.
      ## Preserve bare channel + status prefix character.
      $targets{$target}
        = [ 'channel_prefixed', substr($target, 1), $t_prefix ] ;
      next TARGET
    }

    if (index($target, '$$') == 0) {
      ## Server mask - $$mask
      my $mask = substr($target, 2);
      ## FIXME err if $mask has no length?
      $targets{$target} = [ 'servermask', $mask ];
    }

    if (index($target, '$#') == 0) {
      ## Host mask - $#mask
      my $mask = substr($target, 2);
      $targets{$target} = [ 'hostmask', $mask ];
      next TARGET
    }

    if (index($target, '@') >= 0) {
      ## nick@server (we think)
      my ($nick, $server) = split /@/, $target, 2;
      my $host;
      ($nick, $host) = split /%/, $nick, 2 if $nick =~ /%/;
      $targets{$target} = [
        'nick_fully_qualified',
        $nick, $server, $host
      ];
      ## FIXME push error if no valid args?
      ##  See notes in handle_message_relay also
      next TARGET
    }

    ## FIXME support local-server nick%host also?

    ## Fall through to nickname
    $targets{$target} = [ 'nick' ];
  } ## TARGET


  wantarray ? (\%targets, $err_set) : \%targets
}


1;
