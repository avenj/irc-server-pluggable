package IRC::Server::Pluggable::Protocol::Role::Channels;

use Carp;
use Moo::Role;
use strictures 1;

require Scalar::Utils;

requires qw/
  channels
  users

  numeric

  send_to_routes
/;

### ->chan_user_can_join( $user_obj, $chan_name, %join_opts )
### ->chan_user_can_send( $user_obj, $chan_name )

## FIXME methods for:
##  - channel creation (+ process / event events)
##  - actual protocol join action (+ process / emit events)
##  - dispatched channel modes method?
##    dispatch out of a Role::Mode or so?

## FIXME
## Pass actions/timestamps/args to burst_* methods for verification?
# sub irc_ev_client_cmd_join {}
# sub irc_ev_peer_cmd_join {}
# sub irc_ev_peer_cmd_sjoin {}

sub chan_user_can_join {
  ## chan_user_can_join( $user_obj, $chan_name, key => $key, . . . )
  my ($self, $user_obj, $chan_name, %opts) = @_;

  return unless $self->__r_channels_check_user_arg($user_obj);

  my $channels = $self->channels;

  my $chan_obj = $channels->by_name($chan_name);
  unless ( $chan_obj ) {
    ## FIXME channel creation method
  }

  ## Services can always join.
  return 1 if $user_obj->is_flagged_as('SERVICE');

  ## This +b check allows invite-past-ban.
  if ( $channels->user_is_banned($user_obj, $chan_name)
    && !$channels->user_is_invited($user_obj, $chan_name) ) {

    my $output = $self->__r_channels_get_numeric(
       474, $user_obj->nick, $chan_name
    );

    $self->send_to_routes( $output, $user_obj->route );
    return
  }

  ## Invite-only (+i) check
  if ( $channels->channel_has_mode($chan_name, 'i')
    && !$channels->user_is_invited($user_obj, $chan_name) ) {

    my $output = $self->__r_channels_get_numeric(
      473, $user_obj->nick, $chan_name
    );

    $self->send_to_routes( $output, $user_obj->route );
    return
  }

  ## Key (+k) check
  ## Key should be passed along in params, see docs
  if ( $opts{key} && my $ckey = $chan_obj->channel_has_mode('k') ) {

    unless ( $opts{key} eq $ckey ) {
      my $output = $self->__r_channels_get_numeric(
        475, $user_obj->nick, $chan_name
      );

      $self->send_to_routes( $output, $user_obj->route );
      return
    }

  }

  ## Limit +l check
  if ( my $limit = $chan_obj->channel_has_mode('l') ) {
    if ( keys(%{ $chan_obj->nicknames }) >= $limit ) {

      my $output = $self->__r_channels_get_numeric(
        471, $user_obj->nick, $chan_name
      );

      $self->send_to_routes( $output, $user_obj->route );
      return
    }
  }

  ## Extra subclass checks (ssl-only, reg-only, ...) can be implemented
  ## In a subclass:
  ##  around 'user_can_join' => sub {
  ##    my ($orig, $self, $user, $chan_name, %opts) = @_;
  ##    ## Check if super (here) would allow this user:
  ##    return unless $self->$orig($user, $chan_name, %opts);
  ##    . . . extra checks here . . .
  ##  };

  1
}

sub chan_user_can_send {
  my ($self, $user_obj, $chan_name) = @_;

  return unless $self->__r_channels_check_user_arg($user_obj);

  return 1 if $user_obj->is_flagged_as('SERVICE');

  my $channels = $self->channels;

  if ( $channels->user_is_present($user_obj, $chan_name) ) {
    ## User is present, if they have status modes,
    ## the message should pass
    return 1
  } else {
    ## User is not present; if +n is set, drop message
    return if $channels->channel_has_mode($chan_name, 'n')
  }

  ## user_is_moderated is false if the user has status modes
  ## See IRC::Channels base class
  return if $channels->user_is_moderated($user_obj, $chan_name);

  ## Can't send if banned unless the user is present and has status.
  ## If that is the case, we already returned true above.
  return if $channels->user_is_banned($user_obj, $chan_name);

  ## User can send to channel.
  1
}


### Internals.

sub __r_channels_check_user_arg {
  my $self = shift;
  ## Allow methods to take either a user_obj or an identifier
  ## Attempt to modify caller's args
  ## If we can't get either, carp and return
  ## FIXME it's possible this should live as a role method
  unless ( Scalar::Utils::blessed($_[0]) ) {
    $_[0] = $self->users->by_name($_[0]);
    unless ($_[0]) {
      my $called = (caller(1))[3];
      carp "$called nonexistant user specified";
      return
    }
  }
  $_[0]
}

sub __r_channels_get_numeric {
  my ($self, $numeric, $target, @params) = @_;

  ## FIXME very possible this should live in a Role method

  $self->numeric->to_hash( $numeric,
    prefix => $self->config->server_name,
    target => $target,
    params => \@params,
  )
}

1;
