package IRC::Server::Pluggable::Protocol::Role::Messages;

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

use constant {
  CHANNEL       => 1,
  NICK          => 2,
  NICK_FULLQUAL => 3,
  CHAN_PREFIX   => 4,
  SERVERMASK    => 5,
  HOSTMASK      => 6,
};

use namespace::clean;

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


with 'IRC::Server::Pluggable::Role::Interface::IRCd';
requires qw/
  channel_types
  user_cannot_send_to_chan
/;


### Command handlers.

sub cmd_from_client_privmsg {
  my ($self, $conn, $ev, $user) = @_;

  unless (@{ $ev->params }) {
    $self->send_numeric( 461,
      target => $user->nick,
      params => [ 'PRIVMSG' ],
      routes => $user->route,
    );
    return
  }

  unless (@{ $ev->params } >= 2) {
    $self->send_numeric( 412,
      target => $user->nick,
      routes => $user->route,
    );
    return
  }

  $self->handle_message_relay(
    type     => 'privmsg',
    src_conn => $conn,
    prefix   => $user->nick,
    targets  => [ split /,/, $ev->params->[0] ],
    string   => $ev->params->[1],
  );
}

sub cmd_from_client_notice {
  my ($self, $conn, $ev, $user) = @_;

  unless (@{ $ev->params }) {
    $self->send_numeric( 461,
      target => $user->nick,
      params => [ 'NOTICE' ],
      routes => $user->route,
    );
    return
  }

  ## No other error numerics for NOTICE, per RFC.
  return unless @{ $ev->params } >= 2;

  $self->handle_message_relay(
    type      => 'notice',
    src_conn  => $conn,
    prefix    => $user->nick,
    targets   => [ split /,/, $ev->params->[0] ],
    string    => $ev->params->[1],
  );
}

sub cmd_from_peer_privmsg {
  my ($self, $conn, $ev, $peer) = @_;

  ## FIXME should we be returning errors ?
  unless (@{ $ev->params }) {
  }

  unless (@{ $ev->params } >= 2) {
  }

  $self->handle_message_relay(
    type      => 'privmsg',
    src_conn  => $conn,
    prefix    => $ev->prefix,
    targets   => [ split /,/, $ev->params->[0] ],
    string    => $ev->params->[1],
  );
}


sub cmd_from_peer_notice {
  my ($self, $conn, $ev, $peer) = @_;

  return unless @{ $ev->params } >= 2;

  $self->handle_message_relay(
    type     => 'notice',
    src_conn => $conn,
    prefix   => $ev->prefix,
    targets  => [ split /,/, $ev->params->[0] ],
    string   => $ev->params->[1],
  );
} 



### Public util methods.

sub user_cannot_send_to_user {
  ## FIXME
  ##  User-to-user counterpart to Channels->user_cannot_send_to_chan
}


### Relaying.


sub r_msgs_parse_targets {
  my ($self, $user, $type, @targetlist) = @_;
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

  confess "Expected a source user object" unless blessed $user;

  my @chan_prefixes   = keys %{ $self->channel_types };
  my @status_prefixes = $self->channels->available_status_modes;

  my %targets;

  my $err_set = eventset();

  TARGET: for my $target (@targetlist) {

    my $t_prefix = substr($target, 0, 1);
 
    if (grep {; $t_prefix eq $_ } @chan_prefixes) {
      ## Message to channel target.
      $targets{$target} = [ CHANNEL ];
      next TARGET
    }
 
    if (grep {; $t_prefix eq $_ } @status_prefixes) {
      ## Message to status target.
      my $c_prefix = substr($target, 1, 1);
      unless (grep {; $c_prefix eq $_ } @chan_prefixes) {
        ## Not a channel.
        $err_set->push(
          $self->numeric->to_hash( 401,
            target => $user->nick,
            prefix => $self->config->server_name,
            ## This is hyb7 behavior:
            params => [ substr($target, 1) ],
          )
        );
        next TARGET
      }
      ## Change target to bare channel name.
      ## Preserve bare channel + status prefix character.
      $targets{$target}
        = [ CHAN_PREFIX, substr($target, 1), $t_prefix ] ;
      next TARGET
    }

    if (index($target, '$$') == 0) {
      ## Server mask - $$mask
      my $mask = substr($target, 2);
      ## FIXME err if $mask has no length?
      $targets{$target} = [ SERVERMASK, $mask ];
      next TARGET
    }

    if (index($target, '$#') == 0) {
      ## Host mask - $#mask
      my $mask = substr($target, 2);
      $targets{$target} = [ HOSTMASK, $mask ];
      next TARGET
    }

    if (index($target, '@') >= 0) {
      ## nick@server (we think)
      my ($nick, $server) = split /@/, $target, 2;
      my $host;
      ($nick, $host) = split /%/, $nick, 2 if $nick =~ /%/;

      unless ($nick) {
        ## No recipient.
        $err_set->push(
          $self->numeric->to_hash( 411,
            target => $user->nick,
            prefix => $self->config->server_name,
            params => [ uc($type) ],
          )
        );
        next TARGET
      }
      
      unless ($server) {
        $err_set->push(
          $self->numeric->to_hash( 401,
            target => $user->nick,
            prefix => $self->config->server_name,
            params => [ $target ],
          )
        );
        next TARGET
      }

      ## FIXME handle mask validation here .. ?
      ##   see notes in handle_message_relay
 
      $targets{$target} = [
        NICK_FULLQUAL,
        $nick, $server, $host
      ];
      next TARGET
    }

    ## FIXME support local-server nick%host also?

    ## Fall through to nickname
    $targets{$target} = [ NICK ];
  } ## TARGET


  wantarray ? (\%targets, $err_set) : \%targets
}

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
    ## FIXME handle src eq spoofed? these should still have a user obj
  }

  my $target_array = ref $params{targets} eq 'ARRAY' ?
    $params{targets} : [ $params{targets} ];

  ## May or may not have a source User obj for originator:
  my ($parsed_prefix) = parse_user($params{prefix});
  my $src_user_obj    = $self->users->by_name($parsed_prefix);

  my ($targetset, $err_set) = $self->r_msgs_parse_targets(
    $src_user_obj, $params{type}, @$target_array
  );

  my $max_msg_targets = $self->config->max_msg_targets;
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

    for ($t_type) {
      when (CHANNEL) {
        $self->r_msgs_relay_to_channel(
          $target, $err_set, \%params, $parsed_prefix, $src_user_obj
        );
      }

      when (NICK) {
        $self->r_msgs_relay_to_nick(
          $target, $err_set, \%params, $parsed_prefix, $src_user_obj
        );
      }

      ## Message to nick@server or nick%host@server
      when (NICK_FULLQUAL) {
        $self->r_msgs_relay_to_nick_fullyqual(
          $target, $err_set, \%params, $parsed_prefix,
          \@t_params, $src_user_obj
        );
      }

      ## Message to prefixed channel (e.g. @#channel)
      when (CHAN_PREFIX) {
        $self->r_msgs_relay_to_channel_prefixed(
          $target, $err_set, \%params, $parsed_prefix,
          \@t_params, $src_user_obj
        );
      }


      ## Message to $$servermask
      when (SERVERMASK) {
        $self->r_msgs_relay_to_servermask(
          $target, $err_set, \%params, $parsed_prefix,
          \@t_params, $src_user_obj
        );
      }

      ## Message to $#hostmask
      when (HOSTMASK) {
        $self->r_msgs_relay_to_hostmask(
          $target, $err_set, \%params, $parsed_prefix,
          \@t_params, $src_user_obj
        );
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

sub r_msgs_relay_to_channel {
  my ($self, $target, $err_set, $params, $parsed_prefix, $src_user_obj) = @_;

  my $chan_obj;
  unless ($chan_obj = $self->channels->by_name($target)) {
    ## No such channel (401)
    $err_set->push(
      $self->numeric->to_hash( 401,
        prefix => $self->config->server_name,
        params => [ $target ],
        target => $parsed_prefix,
      )
    );
    return
  }

  my $routes = $self->r_msgs_accumulate_targets_channel($chan_obj);

  ## Could override to provide v3 intents<->ctcp translation f.ex

  ## If we don't have a src_user_obj, it's likely safe to assume that
  ## this is a spoofed message-from-server or suchlike.
  ## If we do, see if they can send.
  if (defined $src_user_obj &&
     (my $err = $self->user_cannot_send_to_chan($src_user_obj, $target)) ) {
    $err_set->push($err);
    return
  }

  my %out = (
     command => $params->{type},
     params  => [ $target, $params->{string} ],
  );

  delete $routes->{ $params->{src_conn}->wheel_id };
  for my $id (keys %$routes) {
    my $route_type = $self->r_msgs_get_route_type($id) || next;
    my $src_prefix =
      $self->r_msgs_gen_prefix_for_type($route_type, $src_user_obj)
      || $params->{prefix};

    my $ref = { prefix => $src_prefix, %out };

    $self->send_to_routes($ref, $id)
  }

  $routes
}

sub r_msgs_relay_to_nick {
  my ($self, $target, $err_set, $params, $parsed_prefix, $src_user_obj) = @_;

  ## FIXME check for cannot_send

  my $target_user_obj;
  unless ($target_user_obj = $self->users->by_name($target)) {
    $err_set->push(
      $self->numeric->to_hash( 401,
        prefix => $self->config->server_name,
        params => [ $target ],
        target => $parsed_prefix,
      )
    );
    return
  }

  my $src_prefix = $target_user_obj->has_conn ?
    $target_user_obj->full : $target_user_obj->nick ;

  my $ref = {
    prefix  => $src_prefix,
    command => $params->{type},
    params  => [ $target, $params->{string} ],
  };

  $self->send_to_routes( $ref, $target_user_obj->route )
}

sub r_msgs_relay_to_nick_fullyqual {
  my ($self, $target, $err_set, $params, $parsed_prefix,
      $target_params, $src_user_obj) = @_;
  my ($nick, $server, $host) = @$target_params;

  ## FIXME check for cannot_send

  my $target_user_obj;
  unless ($target_user_obj = $self->users->by_name($nick)) {
    $err_set->push(
      $self->numeric->to_hash( 401,
        prefix => $self->config->server_name,
        params => [ $target ],
        target => $parsed_prefix,
      )
    );
    return
  }

  if (defined $host && lc($host) ne lc($target_user_obj->host) ) {
    ## May or may not have a host.
    ## If we do and this user isn't a match, 401:
    $err_set->push(
      $self->numeric->to_hash( 401,
        prefix => $self->config->server_name,
        params => [ $target ],
        target => $parsed_prefix,
      )
    );
    return
  }

  my $peer;
  ## Might be us, might be remote.
  unless (lc($server) eq lc($self->config->server_name)
          || ($peer = $self->peers->by_name($server)) ) {
    $err_set->push(
      $self->numeric->to_hash( 402,
        prefix => $self->config->server_name,
        params => [ $server ],
        target => $parsed_prefix,
      )
    );
    return
  }

 ## FIXME check cannot_send_to_user only if local...?
 ## FIXME relays .. Relay to peer if not us
}

sub r_msgs_relay_to_channel_prefixed {
  my ($self, $target, $err_set, $params, $parsed_prefix,
      $target_params, $src_user_obj) = @_;
  my ($channel, $status_prefix) = @$target_params;

  my $chan_obj;
  unless ($chan_obj = $self->channels->by_name($channel)) {
    $err_set->push(
      $self->numeric->to_hash( 401,
        prefix => $self->config->server_name,
        params => [ $channel ],
        target => $parsed_prefix,
      )
    );
    return
  }

  my $routes = $self->r_msgs_accumulate_targets_statustype(
    $status_prefix,
    $chan_obj
  );
 
  ## FIXME should we be using chan ($target) or each actual target user
  ##  (would have to call by_id for each)?
  my %out = (
     command => $params->{type},
     params  => [ $target, $params->{string} ],
  );

  delete $routes->{ $params->{src_conn}->wheel_id };

  for my $id (keys %$routes) {
    my $route_type = $self->r_msgs_get_route_type($id) || next;
    my $src_prefix =
      $self->r_msgs_gen_prefix_for_type($route_type, $src_user_obj)
      || $params->{prefix};

    my $ref = { prefix => $src_prefix, %out };

    $self->send_to_routes($ref, $id)
  }
  ## FIXME what're the can-send rules here ...?

  $routes
}

sub r_msgs_relay_to_servermask {
  my ($self, $target, $err_set, $params, $parsed_prefix,
      $target_params, $src_user_obj) = @_;

        ## FIXME add relevant local users if we match also
        ## FIXME 481 if not an oper
}

sub r_msgs_relay_to_hostmask {
  my ($self, $target, $err_set, $params, $parsed_prefix,
      $target_params, $src_user_obj) = @_;

        ## FIXME 481 if not an oper
}



### Routes & prefixes.

sub r_msgs_get_route_type {
  my ($self, $route_id) = @_;
  ## FIXME this should move to a more generalized role ...
  ## Determine a remote route's type given an ID

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
  CHAN_MEMBER: for my $nick (@{ $chan->nicknames_as_array }) {
    my $user  = $self->users->by_name($nick);
    next CHAN_MEMBER if $user->is_flagged_as('DEAF');
    $routes{ $user->route() }++
  }

  \%routes
}

sub r_msgs_accumulate_targets_servermask {
  ## $$mask targets
  my ($self, $mask) = @_;

  my @peers = $self->peers->matching($mask);

  my %routes;
  for my $peer (@peers) {
    $routes{ $peer->route() }++
  }

  \%routes
}

sub r_msgs_accumulate_targets_hostmask {
  ## $#mask targets
  my ($self, $mask) = @_;
  my @users = $self->users->nuh_matching($mask);

  my %routes;
  for my $user (@users) {
    $routes{ $user->route() }++;
  }

  \%routes
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

  \%routes
}


1;

=pod

=head1 NAME

IRC::Server::Pluggable::Protocol::Role::Messages

=head1 SYNOPSIS

  ## Handles:
  cmd_from_client_privmsg
  cmd_from_client_notice
  cmd_from_peer_privmsg
  cmd_from_peer_notice

  ## Provides:
  ->handle_message_relay(
    FIXME
  )
  # Returns no useful value.

  ->user_cannot_send_to_user(
  
  )
  # Returns an IRC::Event containing an error numeric.
  # Returns empty list if there were no errors.

=head1 DESCRIPTION

A Protocol::Role providing IRC message relay functionality.

Supported target types:

  Nickname  (nick)
  Addressed (nick@server)
            (nick%host@server)
  Channel   (#channel)
  Status    (@#channel)
  Server    ($$mask)
  Hostmask  ($#mask)

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
