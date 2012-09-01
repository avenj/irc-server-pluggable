package IRC::Server::Pluggable::IRC::Channel;
## Base class for Channels.
## Overridable by Protocols.

use 5.12.1;
use strictures 1;

use overload
  bool     => sub { 1 },
  '""'     => 'name',
  fallback => 1;

use Carp;
use Moo;

use IRC::Server::Pluggable qw/
  Types
  Utils
/;

has 'name' => (
  required => 1,
  is       => 'ro',
  isa      => Str,
);

has 'nicknames' => (
  lazy    => 1,
  is      => 'ro',
  isa     => HashRef[ArrayRef],
  writer  => 'set_nicknames',
  default => sub { {} },
);

has 'modes' => (
  ##  Channel control modes
  ##  Status modes are handled via nicknames hash and chg_status()
  ##  List modes are handled via ->lists
  lazy    => 1,
  is      => 'ro',
  isa     => HashRef,
  writer  => 'set_modes',
  default => sub { {} },
);

has 'topic' => (
  ## Array of topic details
  ##  [ string, setter, TS ]
  lazy      => 1,
  is        => 'ro',
  isa       => Array,
  writer    => 'set_topic',
  predicate => 'has_topic',
  clearer   => 'clear_topic',
  default   => sub { [ ] },
);

has 'ts' => (
  ## Channel's timestamp.
  ## Most common Protocols can make use of this.
  required => 1,
  is       => 'ro',
  isa      => Num,
  writer   => 'set_ts',
  clearer  => 'clear_ts',
);


has '_list_classes' => (
  ## Map list keys to classes
  init_arg => 'list_classes',
  lazy    => 1,
  is      => 'ro',
  isa     => HashRef,
  writer  => '_set_list_classes',
  builder => '_build_list_classes',
);

sub _build_list_classes {
  my $base = "IRC::Server::Pluggable::IRC::Channel::List::";
  {
      bans    => $base . "Bans",
      invites => $base . "Invites",
  }
}


has 'lists' => (
  ## Ban lists, etc
  lazy    => 1,
  is      => 'ro',
  isa     => HashRef,
  writer  => 'set_lists',
  builder => '_build_lists',
);

sub _build_lists {
  ## Construct from _list_classes
  my ($self) = @_;

  my $listref = {};

  for my $key (keys %{ $self->_list_classes }) {
    my $class = $self->_list_classes->{$key};

    require $class;

    $listref->{$key} = $class->new;
  }

  $listref
}


## IMPORTANT: These functions all currently expect a higher
##  level layer to handle upper/lower case manipulation.
##  May reconsider this later ...


### Users

sub add_nickname {
  my ($self, $nickname, $data) = @_;

  ## Map a nickname to an array of status modes.
  ## Note that User manip should be handled out of a Channels collection
  ## and lowercasing should happen there.

  confess "add_user called with no nickname specified"
    unless defined $nickname;

  if (defined $data && ref $data ne 'ARRAY') {
    carp "add_user passed non-ARRAY params argument for $nickname";
    return
  }

  $self->nicknames->{$nickname} = $data // []
}

sub del_nickname {
  my ($self, $nickname) = @_;

  delete $self->nicknames->{$nickname}
}

sub users_as_array {
  my ($self) = @_;

  [ keys %{ $self->nicknames } ]
}

sub _param_isa_user_obj {
  my ($self, $obj) = @_;
  return unless is_Object($user)
    and $user->isa('IRC::Server::Pluggable::IRC::User');
  1
}

sub nickname_has_mode {
  my ($self, $nickname, $modechr) = @_;

  my @modes = @{ $self->nicknames->{$nickname} || return };

  return unless grep { $_ eq $modechr } @modes;

  1
}

sub channel_has_mode {
  my ($self, $modechr) = @_;
  confess "channel_has_mode expects a mode character"
    unless defined $modechr;

  $self->modes->{$modechr}
}

sub channel_has_nickname {
  my ($self, $nickname) = @_
  confess "channel_has_user expects a lowercased nickname"
    unless defined $nickname;

  $self->nicknames->{$nickname}
}


### Modes

sub chg_status {
  ## ->chg_status( $nickname, $mode_to_add, $excluded_modes )
  ##  (For example, +o excludes +h on some implementations.)
  my ($self, $nickname, $modestr, $exclude) = @_;

  confess "chg_status() called with no nickname specified"
    unless defined $nickname;

  confess "chg_status() called with no mode string specified"
    unless defined $modestr;

  my $final;
  unless ($final = $self->nicknames->{$nickname}) {
    carp
      "chg_status() called on $nickname but not present on ".$self->name;

    return
  }

  if (defined $exclude && (my @splitex = split //, $exclude) ) {
   ## FIXME
   ##  smart-match needs to go and this is probably stupid.
    $final = [ grep { !($_ ~~ @splitex) } @$final ]
  }

  push @$final, split //, $modestr;

  $self->nicknames->{$nickname} = [ sort @$final ];
}

sub chg_modes {
  ## FIXME take a hash from mode_to_hash
  ## Modes may have certain side-effects in a Protocol,
  ## Channels should probably bridge
}

## FIXME topic methods


1;
