package IRC::Server::Pluggable::Protocol::Role::Channels;

use Carp;
use Moo::Role;
use strictures 1;

use Scalar::Util 'blessed';

use namespace::clean -except => 'meta';

requires qw/
  channels
  numeric
  peers
  users
  send_numeric
  send_to_routes
/;


## FIXME join methods, call Channels->add_user_to_channel?
## FIXME same for part

sub cmd_from_client_join {

}

sub cmd_from_peer_join {

}

sub cmd_from_peer_sjoin {

}

sub cmd_from_client_part {

}

sub cmd_from_peer_part {

}


## FIXME methods for:
##  - channel creation (+ process / event events)
##  - actual protocol join action (+ process / emit events)
##  - dispatched channel modes method?
##    dispatch out of a Role::Mode or so?

## FIXME
## Pass actions/timestamps/args to burst_* methods for verification?

## FIXME channel-related commands?

#### Joinable/sendable checks.

## +b check/send
sub _r_channels_chk_user_banned {
  my ($self, $channels, $chan_name, $user_obj) = @_;

  ## This +b check allows invite-past-ban.
  return 1 if not $channels->user_is_invited($user_obj, $chan_name)
    and $channels->user_is_banned($user_obj, $chan_name);

  return
}

sub _r_channels_send_user_banned {
  my ($self, $user_obj, $chan_name) = @_;

  $self->send_numeric( 474,
    target => $user_obj->nick,
    params => [ $chan_name ],
    routes => $user_obj->route,
  );
}


## +i check/send
sub _r_channels_chk_invite_only {
  my ($self, $channels, $chan_name, $user_obj) = @_;

  return 1 if not $channels->user_is_invited($user_obj, $chan_name)
           and $channels->channel_has_mode($chan_name, 'i');

  return
}

sub _r_channels_send_invite_only {
  my ($self, $user_obj, $chan_name) = @_;

  $self->send_numeric( 473,
    target => $user_obj->nick,
    params => [ $chan_name ],
    routes => $user_obj->route,
  );
}


## +l check/send
sub _r_channels_chk_over_limit {
  my ($self, $chan_obj) = @_;

  my $limit = $chan_obj->channel_has_mode('l') || return;

  return 1 if keys %{ $chan_obj->nicknames } >= $limit;

  return
}

sub _r_channels_send_over_limit {
  my ($self, $user_obj, $chan_name) = @_;

  $self->send_numeric( 471,
    target => $user_obj->nick,
    params => [ $chan_name ],
    routes => $user_obj->route,
  );
}

## +k send, comparison happens in _r_channels_user_can_join
sub _r_channels_send_bad_key {
  my ($self, $user_obj, $chan_name) = @_;

  $self->send_numeric( 475,
    target => $user_obj->nick,
    params => [ $chan_name ],
    routes => $user_obj->route,
  );
}

sub _r_channels_user_can_join {
  ## _r_channels_user_can_join( $user_obj, $chan_name, key => $key, . . . )
  ##  Return true if the User can join.
  ##  Return false and dispatches an error numeric to User if not.
  my ($self, $user_obj, $chan_name, %opts) = @_;

  ## Public methods can try to retrieve a user obj from nick, if needed:
  return unless $self->__r_channels_check_user_arg($user_obj);

  my $channels = $self->channels;

  my $chan_obj = $channels->by_name($chan_name);
  unless ( $chan_obj ) {
    ## FIXME channel creation method
  }

  ## Services can always join.
  return 1 if $user_obj->is_flagged_as('SERVICE');

  ## Banned (+b) check
  if
  ($self->_r_channels_chk_user_banned($channels, $chan_name, $user_obj)) {
    $self->_r_channels_send_user_banned( $user_obj, $chan_name );
    return
  }

  ## Invite-only (+i) check
  if
  ($self->_r_channels_chk_invite_only($channels, $chan_name, $user_obj)) {
    $self->_r_channels_send_invite_only( $user_obj, $chan_name );
    return
  }

  ## Key (+k) check
  ## Key should be passed along in params, see docs
  if ( $opts{key} && (my $ckey = $chan_obj->channel_has_mode('k')) ) {
    unless ( $opts{key} eq $ckey ) {
      $self->_r_channels_send_bad_key(
        $user_obj, $chan_name
      );
      return
    }
  }

  ## Limit (+l) check
  if ( $self->_r_channels_chk_over_limit( $chan_obj ) ) {
    $self->_r_channels_send_over_limit(
      $user_obj, $chan_name
    );
    return
  }

  ## Extra subclass checks (ssl-only, reg-only, ...) can be implemented
  ## In a subclass:
  ##  around '_r_channels_user_can_join' => sub {
  ##    my ($orig, $self, $user, $chan_name, %opts) = @_;
  ##    ## Check if super (here) would allow this user:
  ##    return unless $self->$orig($user, $chan_name, %opts);
  ##    . . . extra checks here . . .
  ##  };

  return 1
}


## FIXME
##  482 .. ?
##  user_cannot_join_chan refactor for above also ?
sub user_cannot_send_to_chan {
  ## Return false if user is clear to send to channel.
  ## Return an error numeric IRC::Event if not.
  ## FIXME optionally take a chan_obj instead
  my ($self, $user_obj, $chan_name) = @_;
  $self->__r_channels_check_user_arg($user_obj);

  ## SERVICE can always send.
  return if $user_obj->is_flagged_as('SERVICE');

  my $channels = $self->channels;

  my $cantsend = sub {
    $self->numeric->as_event( 404,
      target => $user_obj->nick,
      prefix => $self->config->server_name,
      params => [ $chan_name ],
    )
  };

  unless ( $channels->user_is_present($user_obj, $chan_name) ) {
    ## External user. Check +n first.
    if ( $channels->channel_has_mode($chan_name, 'n') ) {
      return $cantsend->()
    }
  }

  if ( $channels->user_is_moderated($user_obj, $chan_name) ) {
    return $cantsend->()
  }

  if ( $channels->user_is_banned($user_obj, $chan_name)
    && !$channels->status_char_for_user($user_obj, $chan_name) ) {
    ## Banned and no status modes.
    return $cantsend->()
  }

  ## Good to go.
  return
}


#### Internals.

sub __r_channels_check_user_arg {
  my $self = shift;
  ## Allow methods to take either a user_obj or an identifier
  ## Attempt to modify caller's args
  ## If we can't get either, carp and return
  unless ( blessed($_[0]) ) {
    $_[0] = $self->users->by_name($_[0]);
    unless ($_[0]) {
      my $called = (caller(1))[3];
      carp "$called nonexistant user specified";
      return
    }
  }
  $_[0]
}

1;
