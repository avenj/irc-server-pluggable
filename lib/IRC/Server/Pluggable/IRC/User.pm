package IRC::Server::Pluggable::IRC::User;
## Base class for Users.
## Overridable by Protocols.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable qw/
  Types
  Utils
/;

use Scalar::Util qw/
  blessed
  weaken
/;

use namespace::clean -except => 'meta';
use overload
  bool     => sub { 1 },
  '""'     => 'nick',
  fallback => 1;


has 'channels' => (
  ## Array of channels (weak refs).
  lazy => 1,
  is   => 'ro',
  isa  => ArrayRef,
  predicate => 'has_channels',
  writer    => 'set_channels',
  clearer   => 'clear_channels',
  default   => sub { [] },
);

sub add_channel {
  my ($self, $channel) = @_;

  confess "add_channel expects an IRC::Server::Pluggable::IRC::Channel"
    unless blessed $channel
    and $channel->isa('IRC::Server::Pluggable::IRC::Channel');

  my $name = $channel->name;

  $self->channels->{$name} = $channel;

  weaken($self->channels->{$name});

  $self
}

sub del_channel {
  my ($self, $channel) = @_;
  delete $self->channels->{$channel}
}


has 'conn' => (
  ## Backend::Connect conn obj for a local user.
  ## See route() attrib with regards to remote users.
  lazy => 1,

  ## These are also tracked in Backend; they should be destroyed
  ## from there.
  weak_ref => 1,

  is  => 'ro',
  isa => sub {
    is_Object($_[0])
      and $_[0]->isa('IRC::Server::Pluggable::Backend::Connect')
      or confess "$_[0] is not a IRC::Server::Pluggable::Backend::Connect"
  },

  predicate => 'has_conn',
  writer    => 'set_conn',
  clearer   => 'clear_conn',
);



has 'realname' => (
  required => 1,
  is       => 'ro',
  isa      => Str,
  writer   => 'set_realname',
);

has 'route' => (
  ## Either our conn's wheel_id or the ID of the next hop peer
  ## (ie, the peer that relayed user registration)
  lazy      => 1,
  is        => 'ro',
  isa       => Str,
  writer    => 'set_route',
  predicate => 'has_route',
  clearer   => 'clear_route',
  default   => sub {
    my ($self) = @_;
    ## If we have a conn() we can get a route.
    ## If we don't we should've had a route specified at construction
    ## or died in BUILD.
    $self->conn->wheel_id
  },
);

has 'server' => (
  required => 1,
  is       => 'ro',
  isa      => Str,
  writer   => 'set_server',
);

has 'ts' => (
  is      => 'ro',
  isa     => Num,
  writer  => 'set_ts',
  clearer => 'clear_ts',
  default => sub { time() },
);


## Host information

has 'nick' => (
  required => 1,
  is       => 'ro',
  isa      => Str,
  writer   => 'set_nick',
  trigger  =>  1, ## _trigger_nick
);

has 'user' => (
  required => 1,
  is       => 'ro',
  isa      => Str,
  writer   => 'set_user',
  trigger  =>  1,
);

has 'host' => (
  required => 1,
  is       => 'ro',
  isa      => Str,
  writer   => 'set_host',
  trigger  =>  1,
);

has 'full' => (
  ## To avoid doing string operations every time we need a user
  ## prefix, build and preserve the full nick!user@host
  ## The tradeoff, though, is that trigger for 'nick' 'user' and 'host'
  ## attribs will fire at construction time (for each respective attrib).
  ## The _reset_full trigger below will return unless has_full, so it
  #  is a fairly acceptable sacrifice...
  lazy      => 1,
  is        => 'ro',
  isa       => Str,
  writer    => 'set_full',
  predicate => 'has_full',
  builder   => '_build_full',
);

sub _build_full {
  my ($self) = @_;
  $self->nick .'!'. $self->user .'@'. $self->host
}

## These all do the same thing, but Moo triggers appear to be
## either a coderef or a boolean true value, with little room for
## negotiation. Possible a subclass may want to override to do esoteric
## things anyway:
sub _trigger_user { $_[0]->_trigger_nick(@_[1 .. $#_]) }
sub _trigger_host { $_[0]->_trigger_nick(@_[1 .. $#_]) }
sub _trigger_nick {
  my ($self) = @_;
  $self->set_full( $self->_build_full )
    if $self->has_full
}

## Mode-related.
has '_valid_modes' => (
  ## See _build_valid_modes
  lazy      => 1,
  init_args => 'valid_modes',
  isa       => HashRef,
  is        => 'ro',
  predicate => '_has_valid_modes',
  writer    => '_set_valid_modes',
  builder   => '_build_valid_modes',
);

sub _build_valid_modes {
  ## Override to add valid user modes.
  ## $mode => 0  # Mode takes no params.
  ## $mode => 1  # Mode takes param when set.
  ## $mode => 2  # Mode always takes param.
  +{ 
    map {; $_ => 0 } split '', 'iaows'
  }
}

sub mode_is_valid {
  my ($self, $mode) = @_;
  confess "Expected a mode to be supplied" unless defined $mode;
  return unless defined $self->_valid_modes->{$mode};
  1
}

sub mode_takes_params {
  my ($self, $mode) = @_;
  return 0 unless defined $self->_valid_modes->{$mode};
  $self->_valid_modes->{$mode}
}


has '_modes' => (
  lazy    => 1,
  is      => 'ro',
  isa     => HashRef,
  writer  => '_set_modes',
  default => sub { {} },
);

sub set_mode_from_string {
  my ($self, $modestr, @params) = @_;

  my @list = keys %{ $self->_valid_modes };
  my (@always, @whenset);
  for my $mchr (@list) {
    if ($self->mode_takes_params($_) == 2) {
      push @always, $mchr;
      next
    }
    if ($self->mode_takes_params($_) == 1) {
      push @whenset, $mchr;
      next
    }
  }

  my $array = mode_to_array( $modestr,
    param_always => \@always,
    param_set    => \@whenset,
    params       => \@params,
  );

  $self->set_mode_from_array($array)
}

sub set_mode_from_array {
  my ($self, $modearray) = @_;

  my @changed;
  MODESET: for my $mset (@$modearray) {
    my ($flag, $mode, $param) = @$mset;
    if ($flag eq '+') {
      unless ($self->mode_is_valid($mode)) {
        Carp::cluck "Invalid user modechar $mode";
        next MODESET
      }
      $self->_modes->{$mode} = $param // 1;
      push @changed, [ $flag, $mode, $param ]
    } else {
      push @changed, [ $flag, $mode, delete $self->_modes->{$mode} ]
        if exists $self->_modes->{$mode};
    }
  }

  ## Returns array-of-arrays describing changes.
  ## (in the same format as Utils::mode_to_array)
  \@changed
}


has '_flags' => (
  ## FIXME document reserved keys:
  ##  - SERVICE  Bool
  ##  - DEAF     Bool
  lazy => 1,
  is   => 'ro',
  isa  => HashRef,
  default => sub { {} },
);

sub list_flags {
  my ($self) = @_;
  keys %{ $self->_flags }
}

sub add_flags {
  my ($self, @flags) = @_;
  $self->_flags->{$_} = 1 for @flags;
  1
}

sub del_flags {
  my ($self, @flags) = @_;
  delete $self->_flags->{$_} for @flags;
  1
}

sub is_flagged_as {
  my ($self, @flags) = @_;

  my @resultset;

  for my $to_check (@flags) {
    push(@resultset, $to_check)
      if $self->_flags->{$to_check}
  }

  @resultset
}


has '_metadata' => (
  ## FIXME document reserved keys:
  ##  - CAP      HASH
  ##  - ACCOUNT  String
  lazy    => 1,
  is      => 'ro',
  isa     => HashRef,
  default => sub { {} },
);

sub add_meta {
  my ($self, $key, $value) = @_;
  confess "Expected a key and value"
    unless defined $key and defined $value;
  $self->_metadata->{$key} = $value
}

sub del_meta {
  my ($self, $key) = @_;
  confess "Expected a key" unless defined $key;
  delete $self->_metadata->{$key}
}

sub meta_item {
  my ($self, $key) = @_;
  $self->_metadata->{$key}
}

sub meta_keys {
  my ($self) = @_;
  keys %{ $self->_metadata }
}



sub BUILD {
  my ($self) = @_;

  unless ($self->has_conn || $self->has_route) {
    confess
      "A User needs either a conn() or a route() at construction time"
  }
}


no warnings 'void';
q{
  <Schroedingers_hat> i suppose I could analyse the gif and do a fourier 
   decomposition, then feed that into a linear model and see what 
   happens...
  <Schroedingers_hat> ^ The best part is that sentence was 
   about breasts.
};


=pod

=head1 NAME

IRC::Server::Pluggable::IRC::User - Base class for Users

=head1 SYNOPSIS

FIXME

=head1 DESCRIPTION

A base class for a User belonging to a 
L<IRC::Server::Pluggable::Protocol>.

=head2 Attributes

Attributes can be changed after initialization by prefixing the attribute 
name with B<set_>

=head3 nick

The nickname string for this User.

=head3 user

The username ('ident') string for this User.

=head3 host

The visible hostname string for this User.

=head3 modes

The HASH mapping mode characters to any scalar parameters for same.

Most user modes in most IRC implementations are simple booleans; the 
scalar value for an enabled boolean mode is '1'

Also see L</set_modes> and L</modes_as_string>

=head3 realname

The GECOS / 'real name' string for this User.

=head3 server

The visible server string for this User.

=head2 Methods

=head3 full

This User's full nick!user@host string, composed via the attributes listed 
above.

FIXME

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
