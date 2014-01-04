package IRC::Server::Pluggable::IRC::User;

use Defaults::Modern;

use IRC::Server::Pluggable qw/
  Types
/;

use Scalar::Util 'weaken';

use IRC::Toolkit::Modes;

use Exporter 'import';
our @EXPORT = 'irc_user';
sub irc_user {  __PACKAGE__->new(@_) }

use Moo; use MooX::late;
use overload
  bool     => sub { 1 },
  '""'     => 'nick',
  fallback => 1;


with 'IRC::Server::Pluggable::Role::Metadata';
## FIXME document reserved meta keys:
##  - CAP      HASH
##  - ACCOUNT  String
with 'IRC::Server::Pluggable::Role::Routable';
with 'IRC::Server::Pluggable::Role::SendQueue';

sub BUILD {
  my ($self) = @_;

  unless ($self->has_conn || $self->has_route) {
    confess
      "A User needs either a conn() or a route() at construction time"
  }
}

has channels => (
  lazy      => 1,
  :is        => 'ro',
  isa       => HashObj,
  coerce    => 1,
  predicate => 'has_channels',
  writer    => 'set_channels',
  clearer   => 'clear_channels',
  builder   => sub { hash },
);

method add_channel ( ChanObj $channel ) {
  my $name = $channel->name;
  $self->channels->set($name => $channel);
  weaken($self->channels->{$name});
  $self
}

method del_channel ( (ChanObj | Str) $channel ) {
  # FIXME auto-normalize if not blessed? check this
  $self->channels->delete("$channel")
}


has realname => (
  required => 1,
  is       => 'ro',
  isa      => Str,
  writer   => 'set_realname',
);

has server => (
  required => 1,
  is       => 'ro',
  isa      => Str,
  writer   => 'set_server',
);

has ts => (
  is      => 'ro',
  isa     => Num,
  writer  => 'set_ts',
  clearer => 'clear_ts',
  default => sub { time() },
);


has nick => (
  required => 1,
  is       => 'ro',
  isa      => Str,
  writer   => 'set_nick',
  trigger  =>  1, ## _trigger_nick
);

## A TS6 user will have an ID / UID.
has id => (
  lazy      => 1,
  is        => 'ro',
  isa       => Str,
  writer    => 'set_id',
  predicate => 'has_id',
  builder   => sub {
    # Default to nick() -- a non-TS ircd won't feed us an ID
    my ($self) = @_; $self->nick
  }
);

has uid => (
  ## TS6.txt: UID = sid() . id()
  lazy      => 1,
  is        => 'ro',
  isa       => TS_ID,
  writer    => 'set_uid',
  predicate => 'has_uid',
  builder   => sub {
    confess
      "uid() requested but none specified, is this a TS6 implementation?"
  },
);

has user => (
  required => 1,
  is       => 'ro',
  isa      => Str,
  writer   => 'set_user',
  trigger  => 1,
);

has host => (
  required => 1,
  is       => 'ro',
  isa      => Str,
  writer   => 'set_host',
  trigger  => 1,
);

has full => (
  lazy      => 1,
  is        => 'ro',
  isa       => Str,
  writer    => 'set_full',
  predicate => 'has_full',
  builder   => sub {
    my ($self) = @_;
    $self->nick .'!'. $self->user .'@'. $self->host
  },
);

method _trigger_nick {
  $self->set_full( $self->_build_full ) if $self->has_full
}
{ no warnings 'once'; 
  *_trigger_user = *_trigger_nick;
  *_trigger_host = *_trigger_nick;
}

## Mode-related.
has _valid_modes => (
  ## See _build_valid_modes
  lazy      => 1,
  init_args => 'valid_modes',
  isa       => HashObj,
  coerce    => 1,
  is        => 'ro',
  predicate => '_has_valid_modes',
  writer    => '_set_valid_modes',
  builder   => sub {
    ## Override to add valid user modes.
    ##  $mode => 0  # Mode takes no params.
    ##  $mode => 1  # Mode takes param when set.
    ##  $mode => 2  # Mode always takes param.
    ## This default set is entirely paramless:
    hash( map {; $_ => 0 } split '', 'iaows' )
  },
);

method mode_is_valid (Str $mode)     { !! $self->_valid_modes->exists($mode) }
method mode_takes_params (Str $mode) { $self->_valid_modes->get($mode) // () }


has _modes => (
  lazy    => 1,
  is      => 'ro',
  isa     => HashObj,
  coerce  => 1,
  writer  => '_set_modes',
  builder => sub { hash },
);

method set_mode_from_string (Str $modestr, @params) {
  my @list = $self->_valid_modes->keys->all;
  my (@always, @whenset);

  MODECHAR: for my $mchr (@list) {
    if ($self->mode_takes_params($_) == 2) {
      push @always, $mchr;
      next MODECHAR
    }
    if ($self->mode_takes_params($_) == 1) {
      push @whenset, $mchr;
      next MODECHAR
    }
  }

  my $array = mode_to_array( $modestr,
    param_always => \@always,
    param_set    => \@whenset,
    params       => \@params,
  );

  $self->set_mode_from_array($array)
}

method set_mode_from_array (
  (ArrayObj | ArrayRef) $modearray
) {
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
  array @changed
}


has _flags => (
  ## FIXME document reserved keys:
  ##  - SERVICE  Bool
  ##  - DEAF     Bool
  lazy      => 1,
  is        => 'ro',
  isa       => HashObj,
  builder   => sub { hash },
);

method list_flags { $self->_flags->keys->all }

method add_flags (@flags) {
  $self->_flags->set( map {; $_ => 1 } @flags );
  $self
}

method del_flags (@flags) {
  $self->_flags->delete(@flags);
  $self
}

method is_flagged_as (@flags) {
  my @resultset;
  for my $to_check (@flags) {
    push(@resultset, $to_check) if $self->_flags->exists($to_check)
  }
  @resultset
}


sub BUILDARGS {
  my $self = shift;
  my %opts = @_ ? @_ > 1 ? @_ : %{ $_[0] } : ();

  ## If we were given an ID and SID, we can create our TS6 UID:
  if (defined $opts{id}) {
    confess "'id =>' specified but no 'sid' or 'uid' given"
      unless defined $opts{sid} or defined $opts{uid};

    ## FIXME make sure Register is adding a full UID
    if (defined $opts{sid} && !defined $opts{uid}) {
      $opts{uid} = $opts{sid} . $opts{id}
    }
  }

  \%opts
}


print q{
  <Schroedingers_hat> i suppose I could analyse the gif and do a fourier 
   decomposition, then feed that into a linear model and see what 
   happens...
  <Schroedingers_hat> ^ The best part is that sentence was 
   about breasts.
} unless caller; 
1;

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
