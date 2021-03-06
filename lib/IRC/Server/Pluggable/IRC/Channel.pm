package IRC::Server::Pluggable::IRC::Channel;
# Base class for Channels;
# Types/subclasses are mapped in Protocol.

use Defaults::Modern;

use Module::Runtime 'use_module';

use IRC::Server::Pluggable qw/
  Types
/;

use Exporter 'import';
our @EXPORT = 'irc_channel';
sub irc_channel {
  __PACKAGE__->new(@_)
}


use Moo; use MooX::late;
use overload
  bool     => sub { 1 },
  '""'     => 'name',
  fallback => 1 ;


has is_relayed => (
  lazy    => 1,
  is      => 'ro',
  isa     => Bool,
  writer  => 'set_relayed',
  default => sub { 1 },
);


has _list_classes => (
  # Map list keys to classes
  init_arg => 'list_classes',
  lazy    => 1,
  is      => 'ro',
  isa     => HashObj,
  coerce  => 1,
  writer  => '_set_list_classes',
  builder => '_build_list_classes',
);

method _build_list_classes {
  my $base = "IRC::Server::Pluggable::IRC::Channel::List::";
  hash(
    bans    => $base . "Bans",
    invites => $base . "Invites",
  )
}

has lists => (
  # Ban lists, etc
  lazy    => 1,
  is      => 'ro',
  isa     => TypedHash[Object],
  coerce  => 1,
  writer  => 'set_lists',
  builder => '_build_lists',
);

method _build_lists {
  # Construct from _list_classes
  my $lists = hash;
  for my $key (keys %{ $self->_list_classes }) {
    my $class = $self->_list_classes->{$key};
    $lists->set($key => use_module($class)->new)
  }
  $lists
}


has name => (
  required => 1,
  is       => 'ro',
  isa      => Str,
);

has nicknames => (
  lazy    => 1,
  is      => 'ro',
  isa     => HashRef[ArrayRef],
  writer  => 'set_nicknames',
  default => sub { {} },
);

has _modes => (
  #  Channel control modes
  #  Status modes are handled via nicknames hash and chg_status()
  #  List modes are handled via ->lists
  lazy      => 1,
  is        => 'ro',
  isa       => HashObj,
  coerce    => 1,
  writer    => '_set_modes',
  predicate => '_has_modes',
  default   => sub { hash },
);

has _topic => (
  # Array of topic details
  #  [ string, setter, TS ]
  lazy      => 1,
  is        => 'ro',
  isa       => ArrayObj,
  coerce    => 1,
  writer    => '_set_topic',
  predicate => '_has_topic',
  clearer   => '_clear_topic',
  default   => sub { array },
);

has ts => (
  is       => 'ro',
  isa      => Num,
  writer   => 'set_ts',
  clearer  => 'clear_ts',
  default  => sub { time },
);


has valid_modes => (
  lazy      => 1,
  is        => 'ro',
  isa       => TypedHash[ArrayObj],
  coerce    => 1,
  predicate => 'has_valid_modes',
  writer    => 'set_valid_modes',
  builder   => '_build_valid_modes',
);

method _build_valid_modes {
  # ISUPPORT CHANMODES=1,2,3,4
  # Channel modes fit in four categories:
  #  'LIST'     -> Modes that manipulate list values
  #  'PARAM'    -> Modes that require a parameter
  #  'SETPARAM' -> Modes that only require a param when set
  #  'SINGLE'   -> Modes that take no parameters
  hash(
    LIST     => array( 'b' ),
    PARAM    => array( 'k' ),
    SETPARAM => array( 'l' ),
    SINGLE   => array( split '', 'imnpst' ),
  )
}

method add_valid_mode (Str $type, @modes) {
  confess "Expected a mode type and at least one mode character"
    unless @modes;
  confess "Unknown mode type: '$type'"
    unless $self->valid_modes->exists($type);
  $self->valid_modes->get($type)->push(@modes)->all
}

method mode_is_valid (Str $mode) {
  my @all;
  push @all, @{ $self->valid_modes->{$_} } for keys %{ $self->valid_modes };
  return unless grep {; $_ eq $mode } @all;
  1
}



# IMPORTANT: These functions all currently expect a higher
#  level layer to handle upper/lower case manipulation.
#  May reconsider this later ...
#  In the meantime IRC::Channels needs proxy methods

method add_nickname (
  Str                   $nickname,
  (ArrayObj | ArrayRef) $data = []
) {
  # Map a nickname to an array of status modes.
  # Note that User manip should be handled out of a Channels collection
  # and lowercasing should happen there.
  $data = array(@$data) unless is_ArrayObj $data;
  $self->nicknames->set($nickname => $data // array)
}

method del_nickname (Str $nickname) { $self->nicknames->delete($nickname) }

method nicknames_as_array { $self->nicknames->keys }

method channel_has_mode (Str $modechr) { 
  $self->_modes->exists($modechr) 
}

method channel_has_nickname (Str $nickname) {
  $self->nicknames->exists($nickname)
}

sub chg_status {
  # FIXME API sucks
  # ->chg_status( $nickname, $mode_to_add, $excluded_modes )
  #  (For example, +o excludes +h on some implementations.)
  #  Modes currently accepted as strings.
  #  FIXME should probably accept arrayrefs or IRC::ModeChange also
  my ($self, $nickname, $modestr, $exclude) = @_;

  confess "chg_status() expected at least nickname and mode string"
    unless defined $nickname and defined $modestr;

  my $current;
  unless ($current = $self->nicknames->{$nickname}) {
    carp
      "chg_status() called on $nickname but not present on ".$self->name;
    return
  }

  my @modeset = ( @$current, split(//, $modestr) );

  if (defined $exclude && (my @splitex = split //, $exclude) ) {
    my %excluded = map {; $_ => 1 } @splitex;
    @modeset = [ grep {; !$excluded{$_} } @modeset ];
  }

  # Return arrayref consisting of final modes.
  # These will have to be sorted upstream from here.
  # FIXME return IRC::ModeChange instead?
  $self->nicknames->{$nickname} = [ @modeset ]
}

sub chg_modes {
  my ($self, $channel, $mode_hash) = @_;
  confess "chg_modes() expected a channel name and a mode_to_hash() HASH"
    unless ref $mode_hash eq 'HASH';
  # FIXME
  # Modes may have certain side-effects in a Protocol,
  #  Role::Channels should probably bridge
  # Normalize here and modify ->modes, lists, chg_status
}

# Users -- informational (bans, modes, ...)
method user_has_mode (
  Str $nickname,
  Str $modechr
) {
  my $modes = $self->nicknames->get($nickname) || return;
  $modes->has_any(sub { $_ eq $modechr })
}

method user_is_invited (
  Str     $nickname,
  CaseMap $casemap
) {
  my $invlist = $self->lists->get('invite') || return;
  my $res = $invlist->keys_matching_ircstr($nickname => $casemap);
  !! @$res
}

method hostmask_is_banned (
  Str     $hostmask,
  CaseMap $casemap
) {
  my $blist = $self->lists->get('bans') || return;
  my $res = $blist->keys_matching_mask($hostmask => $casemap);
  !! @$res
}

method set_topic (
  Str  $topic,
  Str  $setter = '',
  Num  $ts     = time
) {
  $self->_set_topic( array($topic, $setter, $ts) )
}

method chg_topic_ts ( 
  Num $ts = time
) {
  $self->_topic->set(2 => $ts)
}

method topic_string { $self->_topic->get(0) }
method topic_setter { $self->_topic->get(1) }
method topic_ts     { $self->_topic->get(2) }

1;
