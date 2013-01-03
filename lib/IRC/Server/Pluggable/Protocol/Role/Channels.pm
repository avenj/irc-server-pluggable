package IRC::Server::Pluggable::Protocol::Role::Channels;

use Carp;
use Moo::Role;
use strictures 1;

use Scalar::Util 'blessed';

use IRC::Server::Pluggable qw/
  IRC::Event
  IRC::EventSet
/;

use namespace::clean;

with 'IRC::Server::Pluggable::Role::Interface::IRCd';

requires 'equal';

## FIXME join methods, call Channels->add_user_to_channel?
## FIXME same for part

## FIXME extended-join

sub cmd_from_client_join {
  my ($self, $conn, $event, $user) = @_;

  unless (@{ $event->params }) {
    ## FIXME bad args rpl
    return
  }

  my @targets = split /,/, $event->params->[0];
  for my $chan_name (@targets) {
    ## FIXME
    ##  Do nothing if user is present
    ##  Otherwise call add-to-channel method
  }
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

## +b check
sub r_channels_chk_user_banned {
  my ($self, $channels, $chan_name, $user_obj) = @_;

  ## This +b check allows invite-past-ban.
  return 1 if not $channels->user_is_invited($user_obj, $chan_name)
    and $channels->user_is_banned($user_obj, $chan_name);

  return
}


## +i check
sub r_channels_chk_invite_only {
  my ($self, $channels, $chan_name, $user_obj) = @_;

  return 1 if not $channels->user_is_invited($user_obj, $chan_name)
           and $channels->channel_has_mode($chan_name, 'i');

  return
}

## +l check
sub r_channels_chk_over_limit {
  my ($self, $chan_obj) = @_;

  my $limit = $chan_obj->channel_has_mode('l') || return;

  return 1 if keys %{ $chan_obj->nicknames } >= $limit;

  return
}


### Public.
sub user_can_join_chan {
  ## user_can_join_chan( $user_obj, $chan_name, key => $key, . . . )
  ##  Return true if the User can join.
  ##  Return false and dispatch errors to user if not.
  ##  (If 'send_errors => 0' is specified, only return boolean without
  ##   dispatch)
  ##  Does not currently check to see if user is over max chan limit here.
  my ($self, $user_obj, $chan_name, %opts) = @_;

  my $err_ev;
  $user_obj = $self->users->by_name($user_obj) unless blessed $user_obj;

  my $channels = $self->channels;

  ## Services can always join.
  return 1 if $user_obj->is_flagged_as('SERVICE');

  ## Can always join a nonexistant channel.
  my $chan_obj = $channels->by_name($chan_name) || return 1;

  JOINCHK: {
    ## Banned (+b) check
    if
    ($self->r_channels_chk_user_banned($channels, $chan_name, $user_obj)) {
      $err_ev = $self->numeric->to_event( 474,
        prefix => $self->config->server_name,
        target => $user_obj->nick,
        params => [ $chan_name ],
      );
      last JOINCHK
    }

    ## Invite-only (+i) check
    if
    ($self->r_channels_chk_invite_only($channels, $chan_name, $user_obj)) {
      $err_ev = $self->numeric->to_event( 473,
        prefix => $self->config->server_name,
        target => $user_obj->nick,
        params => [ $chan_name ],
      );
      last JOINCHK
    }

    ## Key (+k) check
    ## Key should be passed along in params as key => $key
    if ( $opts{key} && (my $ckey = $chan_obj->channel_has_mode('k')) ) {
      ## Keys appear to follow IRC upper/lower rules
      ## (at least, that's what hyb7 does)
      unless ( $self->equal($opts{key}, $ckey) ) {
        $err_ev =  $self->numeric->to_event( 475,
          prefix => $self->config->server_name,
          target => $user_obj->nick,
          params => [ $chan_name ],
        );
        last JOINCHK
      }
    }

    ## Limit (+l) check
    if ( $self->r_channels_chk_over_limit( $chan_obj ) ) {
      $err_ev = $self->numeric->to_event( 475,
        prefix => $self->config->server_name,
        target => $user_obj->nick,
        params => [ $chan_name ],
      );
      last JOINCHK
    }
  } ## JOINCHK

  if ($err_ev) {
    $self->send_to_routes( $err_ev, $user_obj->route )
      unless exists $opts{send_errors} and !$opts{send_errors};
    return $opts{return_errors} ? $err_ev : ()
  }

  return 1
}

sub user_cannot_join_chan {
  my $self = shift;
  my $err_ev = $self->user_can_join_chan( @_,
    send_errors   => 0,
    return_errors => 1,
  );
  return unless blessed $err_ev;
  $err_ev
}


sub user_can_send_to_chan {
  my ($self, $user_obj, $chan_name, %opts) = @_;
  $user_obj  = $self->users->by_name($user_obj) unless blessed $user_obj;
  $chan_name = $chan_name->name if blessed $chan_name;

  ## SERVICE can always send.
  return 1 if $user_obj->is_flagged_as('SERVICE');

  my $channels = $self->channels;

  my $cantsend = sub {
    $self->numeric->to_event( 404,
      target => $user_obj->nick,
      prefix => $self->config->server_name,
      params => [ $chan_name ],
    )
  };

  my $err_ev;

  SENDCHK: {
    unless ( $channels->user_is_present($user_obj, $chan_name) ) {
      ## External user. Check +n first.
      if ( $channels->channel_has_mode($chan_name, 'n') ) {
        $err_ev = $cantsend->()
        last SENDCHK
      }
    }

    if ( $channels->user_is_moderated($user_obj, $chan_name) ) {
      $err_ev = $cantsend->()
      last SENDCHK
    }

    if ( $channels->user_is_banned($user_obj, $chan_name)
      && !$channels->status_char_for_user($user_obj, $chan_name) ) {
      ## Banned and no status modes.
      $err_ev = $cantsend->()
      last SENDCHK
    }
  }

  if ($err_ev) {
    $self->send_to_routes( $err_ev, $user_obj->route )
      unless exists $opts{$send_errors} and !$opts{send_errors};
    return $opts{return_errors} ? $err_ev : ()
  }

  1
}

sub user_cannot_send_to_chan {
  ## Counterpart to can_send; returns empty list or an error event.
  ## Dispatches no messages. Used to accumulate EventSets externally.
  my $self = shift;
  my $err_ev = $self->user_can_send_to_chan( @_, 
    send_errors   => 0,
    return_errors => 1 
  );
  return unless blessed $err_ev;
  $err_ev
}

1;
