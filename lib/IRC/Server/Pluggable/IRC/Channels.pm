package IRC::Server::Pluggable::IRC::Channels;

## Maintain a collection of Channel objects.

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

sub user_can_join {
  ## user_can_join( $user_obj, $chan_name, key => $key, ... )
  my ($self, $user, $chan_name, %opts) = @_;
  confess "Invalid arguments to user_cannot_join"
    unless $self->_param_isa_user_obj($user)
    and defined $chan_name;

  ## FIXME should validation live here or higher up?

  ## FIXME how much behavorial stuff should live here?
  ## Probably just shove it all in this class?

  $chan_name = $self->lower($chan_name);

  unless ( $self->_channels->{$chan_name} ) {
    ## New channel, perhaps?
    ## FIXME higher-level should handle creation, probably
  }

  ## FIXME +i check?
  ## FIXME borrow order-of-operations from hyb

  if ( $self->user_is_banned($user, $chan_name) ) {
    ## FIXME check ident etc also
  }

  if ( $opts{key} ) {
    ## FIXME user specified key check
  }

  ## FIXME +l limit check

  ## FIXME
  ## Need overridable methods to check:
  ##  - Key
  ##  - Limit
  ##  - user_is_banned
  ## Subclasses can override to implement joinflood checks etc
}

sub user_can_send {
  my ($self, $user, $chan_name) = @_;

  if ( $self->user_is_present($user, $chan_name) ) {
      ## FIXME user is present; if they have status modes,
      ## return 1 to let message pass
  } else {
      ## FIXME user not present, check +n
      ## return empty list if +n is set
      ## else continue to moderated/banned/etc checks
  }

  if ( $self->user_is_moderated($user, $chan_name) ) {
      ## FIXME user is moderated, return unless status modes
  }

  if ( $self->user_is_banned($user, $chan_name) ) {
      ## FIXME user is banned, return unless status modes
  }

  1

  ## FIXME
  ## Need overridable methods to check:
  ##  - Moderated (user_is_moderated)
  ##  - Banned  (user_is_banned)
  ##  - External user and cmode +n (user_is_present)
  ##  - Need to be able to easily subclass to add stuff like:
  ##     +q, +R, +M  (override this method))
  ##  - Status modes can talk (user_has_status)
  ##  - Configurable oper override?
}

sub user_is_banned {
  my ($self, $user, $chan_name) = @_;
  ## FIXME consult List:: objects, matches_mask
}

sub user_is_invited {
  my ($self, $user, $chan_name) = @_;
}

sub user_is_moderated {
  my ($self, $user, $chan_name) = @_;
  ## for use by user_can_send, mostly
  ## FIXME
  ##  check $self->channel_has_mode 'm'
  ##  let user speak if $self->get_status_char is boolean true
}

sub user_is_present {
  my ($self, $user, $chan_name) = @_;
  confess "user_is_present expects IRC::User and chan name"
    unless $self->_param_isa_user_obj($user)
    and    defined $chan_name;

  my $chan = $self->_channels->{ $self->lower($chan_name) } || return;

  $chan->channel_has_nickname(
    $self->lower( $user->nick )
  )
}

sub user_has_status {
  my ($self, $user, $chan_name, $modechr) = @_;
  confess "user_has_status expects IRC::User, chan name, mode char"
    unless $self->_param_isa_user_obj($user)
    and    defined $chan_name
    and    defined $modechr;

  my $chan = $self->_channels->{ $self->lower($chan_name) } || return;

  $chan->nickname_has_mode(
    $self->lower( $user->nick ),
    $modechr
  )
}

sub get_pub_or_secret_char {
  my ($self, $chan_name) = @_;
  confess "Expected a channel name"
    unless defined $chan_name;

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

  return '@' if $self->user_has_status($user, $chan_name, 'o');
  return '+' if $self->user_has_status($user, $chan_name, 'v');

  return
}

sub get_status_modes {
  my ($self, $user, $chan_name) = @_;

  $chan_name = $self->lower( $chan_name );
  ## FIXME
  ## Return arrayref of status modes for this user
  ## (Sort by priority?)
}

sub channel_has_mode {
  ## Proxy method to Channel->channel_has_mode()
  my ($self, $chan_name, $modechr) = @_;
  confess "Expected a channel name and mode char"
    unless defined $chan_name and defined $modechr;

  my $chan = $self->_channels->{ $self->lower($chan_name) } || return;
  $chan->channel_has_mode($modechr)
}

## FIXME overridable factory method to create a Channel obj?


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
