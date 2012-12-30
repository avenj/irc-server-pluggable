package IRC::Server::Pluggable::Client::Heavy::State;

use 5.12.1;
use Moo;
use Carp 'carp', 'confess';
use Scalar::Util 'weaken';

use IRC::Server::Pluggable qw/
  Types
  Utils
/;

use MooX::Struct -rw,
  Channel => [ qw/
    name
    %present
    $topic
  / ],

  User    => [ qw/
    account
    nick
    user
    host
    realname
    +is_away
    +is_oper
  / ],

  Topic   => [ qw/
    set_by!
    +set_at
    topic!
  / ],

  ISupport => [ 
    qw/
      casemap!
    /,
    extend_with => sub {
      my ($self, $key, $val) = @_;
      $self->isupport_struct->EXTEND(
        -rw => $key
      ) unless $self->isupport_struct->can($key);
      $self->isupport_struct->$key( $val )
        if defined $val;
    },
  ],
;

## Factory method for subclasses.
sub _create_struct {
  my ($self, $type) = splice @_, 0, 2;
  my $obj;
  for (lc $type) {
    $obj = Channel->new(@_)  when 'channel';
    $obj = ISupport->new(@_) when 'isupport';
    $obj = State->new(@_)    when 'state';
    $obj = Topic->new(@_)    when 'topic';
    $obj = User->new(@_)     when 'user';
    confess "cannot create struct - unknown type $type"
  }
  $obj
}

## String-type, ro, with writers.
##    nick_name
##    server_name
has $_ => (
  lazy    => 1,
  is      => 'ro',
  isa     => Str,
  writer  => '_set_'.$_,
  default => sub { '' },
) for qw/ 
  nick_name 
  server_name 
/;

## HASH-type, ro, without writers.
##    _users
##    _chans
##    _capabs
has $_ => (
  lazy    => 1,
  is      => 'ro',
  isa     => HashRef,
  default => sub { {} },
) for qw/ 
  _users 
  _chans
  _capabs
/;


has 'isupport_struct' => (
  is        => 'ro',
  isa       => Object,
  writer    => '_set_isupport_struct',
  predicate => '_has_isupport_struct',
  default   => sub { ISupport->new(casemap => 'rfc1459') },
);


sub casemap {
  my ($self) = @_;
  $self->isupport_struct->casemap || 'rfc1459'
}
with 'IRC::Server::Pluggable::Role::CaseMap';


sub get_channel {
  my ($self, $channel) = @_;
  confess "Expected a channel name" unless defined $channel;
  $self->_chans->{ $self->upper($channel) }
}

sub get_user {
  my ($self, $nick) = @_;
  confess "Expected a nickname" unless defined $nick;
  $self->_users->{ $self->upper($nick) }
}

sub get_status_prefix {
  my ($self, $channel, $nick, $prefix) = @_;
  confess "Expected a channel and nickname"
    unless defined $channel and defined $nick;

  my $chan_obj = $self->_chans->{ $self->upper($channel) };
  unless (defined $chan_obj) {
    carp "Not currently on $channel - cannot retrieve prefix";
    return ''
  }

  my $pfx_arr = $chan_obj->present->{$nick};
  unless (defined $pfx_arr) {
    carp "User not present on $channel - $nick";
    return ''
  }

  if ($prefix) {
    ## ->get_status_prefix($chan, $nick, '@%')
    for my $lookup (split '', $prefix) {
      return $lookup if grep {; $_ eq $lookup } @$pfx_arr;
    }
    return
  }

  join '', @$pfx_arr
}

sub get_isupport {
  my ($self, $key) = @_;
  confess "Expected a key" unless defined $key;
  $key = lc $key;
  return unless $self->isupport_struct->can($key);
  $self->isupport_struct->$key
}


sub add_capabs {
  my ($self, @cap) = @_;
  @cap = map {; lc $_ } @cap;
  for my $thiscap (@cap) {
    $self->_capabs->{$thiscap} = 1
  }
  @cap
}

sub clear_capabs {
  my ($self, @cap) = @_;
  my @result;
  for my $thiscap (map {; lc $_ } @cap) {
    push @result, delete $self->_capabs->{$thiscap};
  }
  @result
}

sub has_capabs {
  my ($self, @cap) = @_;
  my @result;
  for my $thiscap (map {; lc $_ } @cap) {
    push @result, $thiscap if exists $self->_capabs->{$thiscap};
  }
  @result
}

sub capabs {
  my ($self) = @_;
  keys %{ $self->_capabs }
}

1;

