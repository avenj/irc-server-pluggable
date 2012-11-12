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

use Scalar::Util 'blessed';

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

has '_status_mode_map' => (
  ## Array mapping status mode chars to prefixes
  ## Ordered by priority, high-to-low:
  ##  [ o => '@', v => '+' ]
  ## See _build_status_mode_map
  lazy      => 1,
  is        => 'ro',
  isa       => ArrayRef,
  writer    => '_set_status_mode_map',
  predicate => '_has_status_mode_map',
  builder   => '_build_status_mode_map',
  trigger   => sub {
    my ($self, $value) = @_;
    $self->_set_status_mode_hash({ @$value })
  },
);

has '_status_mode_hash' => (
  ## _status_mode_map inflated to a hash for fast lookups.
  lazy      => 1,
  is        => 'ro',
  isa       => HashRef,
  writer    => '_set_status_mode_hash',
  predicate => '_has_status_mode_map',
  default   => sub {
    my ($self) = @_;
    { @{ $self->_status_mode_map } }
  },
);

sub _build_status_mode_map {
  ## Override to add status modes.
  [
    o => '@',
#   h => '%',
    v => '+',
  ]
}

sub available_status_modes {
  ## The prioritized list.
  my ($self) = @_;

  my @modes;
  my @all = @{ $self->_status_mode_map };

  while (my ($modechr, $prefix) = splice @all, 0, 2) {
    push @modes, $modechr;
  }

  wantarray ? @modes :  [ @modes ]
}

sub status_mode_for_prefix {
  my ($self, $status_prefix) = @_;

  my %modes     = %{ $self->_status_mode_hash };
  my %prefixes  = reverse %modes;

  $prefixes{$status_prefix}
}

sub status_prefix_for_mode {
  my ($self, $status_mode) = @_;

  $self->_status_mode_hash->{$status_mode}
}

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
  my ($self, $user_obj, $chan_name) = @_;

  my $chan = $self->by_name($chan_name) || return;

  return 1 if $chan->hostmask_is_banned( $user_obj->full, $self->casemap );
  return
}

sub user_is_invited {
  my ($self, $user_obj, $chan_name) = @_;

  my $chan = $self->by_name($chan_name) || return;

  return 1 if $chan->user_is_invited( $user_obj->nick, $self->casemap );
  return
}

sub user_is_moderated {
  my ($self, $user_obj, $chan_name) = @_;

  ## User is_moderated is true on a +m channel, unless the user
  ## has status modes.
  ##
  ## Subclasses could override to implement +q, if they liked.

  my $chan = $self->by_name($chan_name) || return;

  return 1 if $self->channel_has_mode($chan_name, 'm')
    and not $self->status_char_for_user($user_obj, $chan_name);

  return
}

sub user_is_present {
  my ($self, $user_obj, $chan_name) = @_;

  my $chan = $self->by_name($chan_name) || return;

  $chan->channel_has_nickname(
    $self->lower( $user_obj->nick )
  )
}

sub user_has_status {
  my ($self, $user_obj, $chan_name, $modechr) = @_;

  my $chan = $self->by_name($chan_name) || return;

  $chan->user_has_mode(
    $self->lower( $user_obj->nick ),
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

sub status_char_for_user {
  my ($self, $user_obj, $chan_name) = @_;

  ## TODO; some newer ircds seem to send '@+' ... worth looking into
  ## We should be sorted highest-to-lowest:
  for my $modechr ($self->available_status_modes) {
    return $self->status_prefix_for_mode($modechr)
      if $self->user_has_status($user_obj, $chan_name, $modechr)
  }

  return
}

sub status_modes_for_user {
  my ($self, $user_obj, $chan_name) = @_;

  my @resultset;
  for my $modechr ($self->available_status_modes) {
    push @resultset, $modechr
      if $self->user_has_status($user_obj, $chan_name, $modechr)
  }

  wantarray ? @resultset : @resultset ? \@resultset : ()
}

sub channel_has_mode {
  ## Proxy method to Channel->channel_has_mode()
  my ($self, $chan_name, $modechr) = @_;

  my $chan = $self->by_name($chan_name) || return;
  $chan->channel_has_mode($modechr)
}

### Add/clear/retrieve methods:
sub add {
  my ($self, $chan) = @_;

  confess "$chan is not a IRC::Server::Pluggable::IRC::Channel"
    unless blessed($chan)
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
