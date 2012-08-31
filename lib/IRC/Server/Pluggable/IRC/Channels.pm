package IRC::Server::Pluggable::IRC::Channels;

## Base Channels class.
## Maintain a collection of Channel objects.
##
## Most channel-specific behavior can be overriden in a Channels
## subclass.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable qw/
  Types
  Utils
/;

has 'protocol' => (
  ## OK, not the cleanest design, but helpers hook back
  ## into Protocol:
  required  => 1,
  weak_ref  => 1,
  is        => 'ro',
  isa       => Object,
  writer    => 'set_protocol',
  clearer   => 'clear_protocol',
  predicate => 'has_protocol',
);

with 'IRC::Server::Pluggable::Role::CaseMap';


has '_channels' => (
  ## Map (lowercased) channel names to Channel objects.
  lazy    => 1,
  is      => 'ro',
  isa     => HashRef,
  default => sub { {} },
);


### Implementation-specific bits.
## A subclass looking to change how Channels work will probably
## want to change the relevant attribs in their Protocol subclass,
## then possibly write a Protocol::$NAME::Channels subclass that
## overrides these:
sub _param_isa_user_obj {
  my ($self, $obj) = @_;
  return unless is_Object($user)
    and $user->isa('IRC::Server::Pluggable::IRC::User');
  1
}

sub _param_isa_chan_obj {
  my ($self, $obj) = @_;
  return unless is_Object($user)
    and $user->isa('IRC::Server::Pluggable::IRC::User');
  1
}

sub add_user_to_channel {
  my ($self, $user, $chan_name) = @_;
  ## FIXME
}

sub del_user_from_channel {
  ## FIXME
}

sub user_can_join {
  ## user_can_join( $user_obj, $chan_name, key => $key, ... )
  my ($self, $user, $chan_name, %opts) = @_;

  ## FIXME should validation live here or add_user_to_channel?
  ##  or higher up?

  unless ( $self->by_name($chan_name) ) {
    ## FIXME
    ## Channel should have been created and added already.
    ## Need to figure out the sanest entrypoint for that.
  }

  ## Could hook a godmode check here, for example.
  return 1 if $user->is_flagged_as('SERVICE');

  ## Banned check.
  ## This one allows invite-past-ban.
  if ( $self->user_is_banned($user, $chan_name) ) {
    unless ( $self->user_is_invited($user, $chan_name) ) {
      my $output = $self->protocol->numeric->to_hash( 474,
        prefix => $self->protocol->config->server_name,
        target => $user->nick,
        params => [ $chan_name ],
      );
      $self->protocol->dispatcher->dispatch( $output, $user->route );
      return
    }
  }

  ## Invite-only check.
  if ( $self->channel_has_mode($chan_name, 'i') ) {
    unless ( $self->user_is_invited($user, $chan_name) ) {
      my $output = $self->protocol->numeric->to_hash( 473,
        prefix => $self->protocol->config->server_name,
        target => $user->nick,
        params => [ $chan_name ],
      );
      $self->protocol->dispatcher->dispatch( $output, $user->route );
      return
    }
  }

  ## FIXME ..invite doesn't override key, does it?
  if ( $opts{key} ) {
    ## FIXME user specified key check against +k mode args
    ##  send numeric and return
  }

  ## FIXME +l limit check, send user CHANNELISFULL if +l
  ##  and the $chan->nicknames key count is too high

  ## Extra subclass checks (ssl-only, reg-only, ...) can be implemented
  ## In a subclass:
  ##  around 'user_can_join' => sub {
  ##    my ($orig, $self, $user, $chan_name, %opts) = @_;
  ##    ## Check if super (here) would allow this user:
  ##    return unless $self->$orig($user, $chan_name, %opts);
  ##    . . . extra checks here . . .
  ##  };
}

sub user_can_send {
  my ($self, $user, $chan_name) = @_;

  return 1 if $user->is_flagged_as('SERVICE');

  if ( $self->user_is_present($user, $chan_name) ) {
    ## User is present; if they have status modes,
    ## return 1 to let message pass
    return 1 if $self->get_status_char($user, $chan_name)
  } else {
    ## User not present; check for +n
    ## If +n is set, message should be dropped
    return if $self->channel_has_mode($chan_name, 'n');
  }

  ## User is returned not moderated if they have status modes
  return if $self->user_is_moderated($user, $chan_name);

  ## If they're present, banned, and have status, we return 1 above
  ## Return here if they're banned and don't have status / not present
  return if $self->user_is_banned($user, $chan_name);

  1

  ## FIXME
  ##  - Configurable oper override?
}

sub user_is_banned {
  my ($self, $user, $chan_name) = @_;

  my $chan = $self->by_name($chan_name) || return;
  my $cmap = $self->protocol->casemap;

  ## Consult Channel::List obj
  for my $ban ( $chan->lists->{bans}->keys ) {
    return $ban if matches_mask( $ban, $user->full, $cmap )
  }

  return
}

sub user_is_invited {
  my ($self, $user, $chan_name) = @_;

  my $chan = $self->by_name($chan_name) || return;
  ## FIXME consult List:: object
}

sub user_is_moderated {
  my ($self, $user, $chan_name) = @_;

  ## User is_moderated is true on a +m channel, unless the user
  ## has status modes.
  ##
  ## Subclasses could override to implement +q, if they liked.

  my $chan = $self->by_name($chan_name) || return;

  return unless $self->channel_has_mode($chan_name, 'm');

  return unless $self->get_status_char($user, $chan_name);

  1
}

sub user_is_present {
  my ($self, $user, $chan_name) = @_;

  my $chan = $self->by_name($chan_name) || return;

  $chan->channel_has_nickname(
    $self->lower( $user->nick )
  )
}

sub user_has_status {
  my ($self, $user, $chan_name, $modechr) = @_;

  my $chan = $self->by_name($chan_name) || return;

  $chan->nickname_has_mode(
    $self->lower( $user->nick ),
    $modechr
  )
}

sub get_pub_or_secret_char {
  my ($self, $chan_name) = @_;

  ## Ref. hybrid7/src/channel.c channel_pub_or_secret()
  ##  '=' if public
  ##  '@' if secret  (+s)
  ##  '*' if private (+p, varies by implementation)

  $self->channel_has_mode($chan_name, 's')    ? '@'
   : $self->channel_has_mode($chan_name, 'p') ? '*'
   : '='
}

sub get_status_char {
  my ($self, $user, $chan_name) = @_;

  ## Override to add prefixes.
  ## TODO; some newer ircds seem to send '@+' ... worth looking into

  return '@' if $self->user_has_status($user, $chan_name, 'o');
  return '+' if $self->user_has_status($user, $chan_name, 'v');

  return
}

sub get_status_modes {
  my ($self, $user, $chan_name) = @_;

  my @resultset;
  for my $mode (qw/ o v /) {
    push(@resultset, $mode)
      if $self->user_has_status($user, $chan_name, $mode)
  }

  \@resultset
}

sub channel_has_mode {
  ## Proxy method to Channel->channel_has_mode()
  my ($self, $chan_name, $modechr) = @_;

  my $chan = $self->by_name($chan_name) || return;
  $chan->channel_has_mode($modechr)
}

## FIXME overridable factory method to create a Channel obj?
## May make it easier to subclass a Channel.

### Add/clear/retrieve methods:
sub add {
  my ($self, $chan) = @_;

  confess "$chan is not a IRC::Server::Pluggable::IRC::Channel"
    unless is_Object($chan)
    and $chan->isa('IRC::Server::Pluggable::IRC::Channel');

  $self->_channels->{ $self->lower($chan->name) } = $chan;

  $chan
}

sub as_array {
  my ($self) = @_;

  [ map { $self->_channels->{$_}->name } keys %{ $self->_channels } ]
}

sub by_name {
  my ($self, $name) = @_;

  unless (defined $name) {
    carp "by_name() called with no name specified";
    return
  }

  $self->_channels->{ $self->lower($name) }
}

sub del {
  my ($self, $name) = @_;

  confess "del() called with no channel specified"
    unless defined $name;

  delete $self->_channels->{ $self->lower($name) }
}

1;

=pod

=cut
