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


use namespace::clean -except => 'meta';


has 'casemap' => (
  required  => 1,
  is        => 'ro',
  isa       => CaseMap,
  writer    => 'set_casemap',
  clearer   => 'clear_casemap',
  predicate => 'has_casemap',
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

sub add_user_to_channel {
  my ($self, $user, $chan_name) = @_;
  ## FIXME
  ## Called from role?
}

sub del_user_from_channel {
  ## FIXME
}

sub user_is_banned {
  my ($self, $user, $chan_name) = @_;

  my $chan = $self->by_name($chan_name) || return;
  my $cmap = $self->casemap;

  ## Consult Channel::List obj
  return 1 if $chan->lists->{bans}
    and $chan->lists->{bans}->keys_matching_mask($user->full, $cmap);

  return
}

sub user_is_invited {
  my ($self, $user, $chan_name) = @_;

  my $chan = $self->by_name($chan_name) || return;
  my $cmap = $self->casemap;

  return 1 if $chan->lists->{invite}
    and $chan->lists->{invite}->keys_matching_ircstr($user->nick, $cmap);

  return
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
