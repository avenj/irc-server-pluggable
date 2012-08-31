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
  ##  Status modes are handled via nicknames hash and chg_status()
  ##  FIXME Relies on ->prefix_map() and ->valid_channel_modes() from
  ##  Protocol to find out what modes actually are/do, so this all has to be
  ##  outside of these per-channel objects or we need weak_refs back
  ##  Probably belongs in a Role.
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

sub add_user {
  my ($self, $nickname, $data) = @_;

  confess "add_user called with no nickname specified"
    unless defined $nickname;

  if (defined $data && ref $data ne 'ARRAY') {
    carp "add_user passed non-ARRAY params argument for $nickname";
    return
  }

  $self->nicknames->{$nickname} = $data // []
}

sub del_user {
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

## FIXME it's possible all of this should move up a level
## to Channels; we're probably going to need a weak_ref to
## our Protocol instance, and it'd be more efficient to
## keep just the one-per-Protocol in Channels.

sub user_is_banned {
  my ($self, $user) = @_;

  confess "user_is_banned got $user, expected ::IRC::User"
    unless $self->_param_isa_user_obj($user);

  ## FIXME consult List:: objects
  ##  Return true if matches_mask
  ##  This means we need to know our casemap.
}

sub user_can_send {
  my ($self, $user) = @_;

  confess "user_can_send got $user, expected ::IRC::User"
    unless $self->_param_isa_user_obj($user);

  ## FIXME
  ## Need some smart methods to check moderated, status modes, etc
  ## Need to be able to flexibly allow users with status modes to
  ## talk through moderated/banned
  ## Need to handle external messages (cmode +n)
  ## Needs to be easily overridable for subclass modes like +q, +R, +M
  ## No-go if disallowed by check methods
  ## Not sure if base Channel class should let opers override
}

sub user_can_join {
  ## FIXME check user_is_banned, check +k / +l
  ## (Subclasses can deal with exemptions, sslonly etc)
}

### Invites

sub add_invite {
  ## FIXME
}

sub del_invite {
  ## FIXME
}


### Modes

sub get_pub_or_secret_char {
  my ($self) = @_;
  ## FIXME
  ## Return '=' if public
  ##        '@' if secret
  ##        '*' if private
  ## see hybrid7/src/channel.c channel_pub_or_secret()
}

sub get_status_char {
  ## FIXME return status char for User
  ##  These are prioritized in Protocol; we may need refs
  ##  back to Protocol.. not really sane.
  ##  Possible the Protocol attribs for cmodes should just move?
  ##  Keeping copies everywhere sucks too.
  ##  Maybe a weak_ref back to the original attrib.
  ### ...maybe a weak_ref back to Protocol.
  my ($self, $user) = @_;
  confess "get_status_char got $user, expected ::IRC::User"
    unless $self->_param_isa_user_obj($user);
}

sub get_status_modes {
  ## FIXME get array of current status modes for User
  ## See notes in get_status_char.
  my ($self, $user) = @_;
  confess "get_status_modes got $user, expected ::IRC::User"
    unless $self->_param_isa_user_obj($user);
}

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
  ## some of them may be handle-able from here.
  ## We should at least be able to map a mode change to
  ## method dispatch (via ->can('"hg_mode_$mode") or so)
  ## or to a coderef invoked against $self perhaps
}

1;
