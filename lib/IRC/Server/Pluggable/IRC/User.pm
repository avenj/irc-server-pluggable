package IRC::Server::Pluggable::IRC::User;
## Base class for Users.
## Overridable by Protocols.

use 5.12.1;
use strictures 1;

use overload
  bool     => sub { 1 },
  '""'     => 'nick',
  fallback => 1;

use Carp;
use Moo;

use namespace::clean -except => 'meta';

use IRC::Server::Pluggable qw/
  Types
  Utils
/;

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

has 'nick' => (
  required => 1,
  is       => 'ro',
  isa      => Str,
  writer   => 'set_nick',
  trigger  =>  '_reset_full',
);

has 'user' => (
  required => 1,
  is       => 'ro',
  isa      => Str,
  writer   => 'set_user',
  trigger  =>  '_reset_full',
);

has 'host' => (
  required => 1,
  is       => 'ro',
  isa      => Str,
  writer   => 'set_host',
  trigger  =>  '_reset_full',
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

sub _reset_full {
  my ($self) = @_;
  $self->set_full( $self->_build_full )
    if $self->has_full
}

has 'server' => (
  required => 1,
  is       => 'ro',
  isa      => Str,
  writer   => 'set_server',
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

has 'modes' => (
  lazy    => 1,
  is      => 'ro',
  isa     => HashRef,
  default => sub { {} },
);

has 'flags' => (
  ## FIXME document flags:
  ##  - SERVICE
  lazy => 1,
  is   => 'ro',
  isa  => HashRef,
  default => sub { {} },
);


sub BUILD {
  my ($self) = @_;

  unless ($self->has_conn || $self->has_route) {
    confess
      "A User needs either a conn() or a route() at construction time"
  }
}


sub is_flagged_as {
  my ($self, @flags) = @_;

  my @resultset;

  for my $to_check (@flags) {
    push(@resultset, $to_check)
      if $self->flags->{$to_check}
  }

  @resultset
}

sub set_modes {
  my ($self, $data) = @_;

  confess "set_modes() called with no defined arguments"
    unless defined $data;

  $data = $self->_parse_mode_str($data)
    unless ref $data;

  $self->_set_modes_from_ref($data)
}

sub _set_modes_from_ref {
  my ($self, $data) = @_;

  my %changed;

  if (ref $data eq 'ARRAY') {

    MODE: for my $mode (@$data) {

      ## Accept [ $flag, $params ] -- default to bool
      my $params = 1;
      if (ref $mode eq 'ARRAY') {
        ($mode, $params) = @$mode;
      }

      my ($chg, $flag) = $mode =~ /^(\+|-)([A-Za-z])$/;

      unless ($chg && $flag) {
        carp "Could not parse mode change $mode";
        next MODE
      }

      ## Boolean flip.
      if ($chg eq '+') {
        unless ($self->modes->{$flag}) {
          ## Add this mode and record the change.
          $self->modes->{$flag} = 1;
          $changed{$flag}       = 1;
        }
      } elsif ($chg eq '-') {
        if ($self->modes->{$flag}) {
          ## Delete this mode and record the change.
          $changed{$flag} = delete $self->modes->{$flag};
        }
      }

    } ## MODE

  } elsif (ref $data eq 'HASH') {

    ## add => [ mode, ... ],
    ## add => [ [ mode, params ], ... ],
    ## del => [ mode, ... ],

    ADD: for my $flag (@{ $data->{add} }) {
      my $params = 1;
      if (ref $flag eq 'ARRAY') {
        ($flag, $params) = @$flag;
      }

      unless ($self->modes->{$flag}
        && $self->modes->{$flag} eq $params) {

        $self->modes->{$flag} = $params;
        $changed{$flag}       = $params;
      }

    }

    DEL: for my $flag (@{ $data->{del} }) {
      if ($self->modes->{$flag}) {
        $changed{$flag} = delete $self->modes->{$flag};
      }
    }

  } else {
    confess "Passed an unknown reference type: ".ref($data)." ($data)"
  }

  \%changed
}

sub _parse_mode_str {
  my ($self, $str) = @_;

  ## FIXME
  ## Doesn't currently handle params at all.
  ## Should be swapped out for Utils::mode_to_hash

  my %res = ( add => [], del => [] );

  my $in_add = 1;
  for my $char (split '', $str) {
    if ($char eq '+') {
      $in_add = 1;
      next
    }

    if ($char eq '-') {
      $in_add = 0;
      next
    }

    if ($char =~ /A-Z/i) {
      push( @{ $res{ ($in_add ? 'add' : 'del') } },  $_ );
      next
    }

    ## ...elsewise no clue what the hell we were given.
    ## (Protocol side should've returned unknown mode)
    carp "Unknown value $char in _parse_mode_str($str)"
  }

  \%res
}

sub modes_as_string {
  my ($self) = @_;
  my $str;
  $str .= $_ for keys %{ $self->modes };
  $str
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

This User's full nick!user@host string.

=head3 modes_as_string

The currently enabled modes for this User as a concatenated string.

=head3 set_modes

C<set_modes> allows for easy mode hash manipulation.

Pass a string:

  $user->set_modes( '+Aow-i' );

Pass an ARRAY:

  $user->set_modes(
    [ '+s', '-c' ],
  );

Pass an ARRAY containing ARRAYs mapping params to a specific mode:

  $user->set_modes(
    [
      [ '+s', $params ],
      '-c',
    ],
  );

Pass a HASH with 'add' and 'del' ARRAYs:

  $user->set_modes( {
    add => [ split '', 'Aow' ],
    del => [ 'i' ],
  } );


=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
