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

  ## FIXME notices should return no error at all
  ##  see http://tools.ietf.org/html/rfc2812#section-3.3

  ## FIXME
  ##  Parse targets
  ##  Call handlers as-needed
  ##  Accumulate EventSet
  my $target_array = ref $params{targets} eq 'ARRAY' ?
    $params{targets} : [ $params{targets} ];

  my ($targetset, $err_set) = $self->r_msgs_parse_targets(@$target_array);

  my $tcount;
  DEST: for my $target (keys %$targetset) {
    my ($t_type, @t_params) = @{ $targetset->{$target} };
    ## FIXME sanity checks, build EventSet if we hit errors
    ## FIXME as much target verif. as possible should probably move to
    ##  r_msgs_parse_targets or some verification proxy method
    ##  (We get our error EventSet from r_msgs_parse_targets anyway)
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

    ## FIXME always delete originator, ie. src_conn->wheel_id from routes

    ## FIXME should be no code in here -- dispatch out from here
    for ($t_type) {
      when ("channel") {
        ## - 401 if channel nonexistant
        unless (my $chan = $self->channels->by_name($t_params[0])) {
          $err_set->push(
            $self->numeric->to_hash( 401,
              prefix => $self->config->server_name,
              params => [ $target ],
              target => $params{prefix},
            )
          ) unless $params{type} eq 'notice';
          next DEST
        }
        ## - call r_msgs_accumulate_targets_channel to get routes
        my %routes = $self->r_msgs_accumulate_targets_channel($chan);
        ## - delete originator ($params{src_conn}->wheel_id)
        delete $routes{ $params{src_conn}->wheel_id() };
        ## FIXME
        ## - find out if this user can send
      }

      when ("nick") {
        my $user;
        unless ($user = $self->users->by_name($t_params[0])) {
          $err_set->push(
            $self->numeric->to_hash( 401,
              prefix => $self->config->server_name,
              params => [ $target ],
              target => $params{prefix},
            )
          ) unless $params{type} eq 'notice';
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


sub user_cannot_send_to_user {
  ## FIXME
  ##  User-to-user counterpart to Channels->user_cannot_send_to_chan
}

## FIXME also see _state_parse_msg_targets in PCSI
##  + cmd_message / peer_message
## some helpful pointers.

sub r_msgs_accumulate_targets_channel {
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
    $routes{ $user->route() } = 1;
  }

  my @routes = keys %routes;
  wantarray ? @routes : \@routes
}

sub r_msgs_accumulate_targets_servermask {
  ## $$mask targets
  my ($self, $mask) = @_;
  my @peers = $self->peers->matching($mask);

  my %routes;
  for my $peer (@peers) {
    $routes{ $peer->route() } = 1;
  }

  my @routes = keys %routes;
  wantarray ? @routes : \@routes
}

sub r_msgs_accumulate_targets_hostmask {
  ## $#mask targets
  my ($self, $mask) = @_;
  my @users = $self->users->nuh_matching($mask);

  my %routes;
  for my $user (@users) {
    $routes{ $user->route() } = 1;
  }

  my @routes = keys %routes;
  wantarray ? @routes : \@routes
}


sub r_msgs_accumulate_targets_statustype {
  ## Status-prefixed targets, ie. @#channel-like targets

}

sub r_msgs_parse_targets {
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

  my @chan_prefixes   = keys %{ $self->channel_types };
  my @status_prefixes = $self->channels->available_status_modes;

  my %targets;

  my $err_set = IRC::Server::Pluggable::IRC::EventSet->new;

  ## Hum. Do not really like this.
  ## Switch to some lightweight obj interface instead?

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
      ## FIXME error hash if no valid args?
      ##  See notes in handle_message_relay also
      next TARGET
    }

    ## Fall through to nickname
    $targets{$target} = [ 'nick' ];
  } ## TARGET


  wantarray ? (\%targets, $err_set) : \%targets
}


1;
