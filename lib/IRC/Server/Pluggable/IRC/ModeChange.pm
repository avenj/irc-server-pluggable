package IRC::Server::Pluggable::IRC::ModeChange;
use 5.12.1;
use strictures 1;

use Carp;
use Moo;
use IRC::Server::Pluggable qw/
  Types
  Utils
/;

use Scalar::Util 'blessed';

sub _str_to_arr {
  ref $_[0] eq 'ARRAY' ? $_[0]
    : [ split //, $_[0] ]
}

use namespace::clean;


has param_always => (
  lazy    => 1,
  is      => 'ro',
  isa     => ArrayRef,
  coerce  => \&_str_to_arr,
  default => sub {
    [ split //, 'bkohv' ]
  }
);

has param_on_set => (
  lazy    => 1,
  is      => 'ro',
  isa     => ArrayRef,
  coerce  => \&_str_to_arr,
  default => sub {
    [ 'l' ]
  }
);

has mode_array => (
  lazy      => 1,
  is        => 'ro',
  isa       => ArrayRef,
  writer    => '_set_mode_array',
  predicate => 'has_mode_array',
  builder   => '_build_mode_array',
);

sub _build_mode_array {
  my ($self) = @_;
  mode_to_array( $self->mode_string,
    param_always => $self->param_always,
    param_set    => $self->param_on_set,
    (
      $self->has_params ? params => $self->params
       : ()
    ),
  );
}

has params => (
  lazy      => 1,
  is        => 'ro',
  isa       => ArrayRef,
  predicate => 'has_params',
  builder   => '_build_params',
  coerce    => \&_str_to_arr,
);

sub _build_params {
  my ($self) = @_;

  my $arr;
  for my $cset (@{ $self->mode_array }) {
    push @$arr, $cset->[2]
      if defined $cset->[2]
  }
  $arr
}

has mode_string => (
  lazy      => 1,
  is        => 'ro',
  isa       => Str,
  predicate => 'has_mode_string',
  writer    => '_set_mode_string',
  builder   => '_build_mode_string',
);

sub _build_mode_string {
  my ($self) = @_;

  my ($pstr, $mstr);
  my $curflag = '';

  for my $cset (@{ $self->mode_array }) {
    my ($flag, $mode, $param) = @$cset;
    if ($flag eq $curflag) {
      $mstr   .= $mode;
      $pstr   .= $param if defined $param;
    } else {
      $mstr   .= $flag . $mode;
      $curflag = $flag;
    }
  }

  $mstr .= " $pstr" if length $pstr;
  $mstr
}


sub split_mode_set {
  ## Split into smaller sets of changes.
  my ($self, $max) = @_;
  $max ||= 4;

  my @new;
  while (my @spl = splice @{ $self->mode_array }, 0, $max) {
    push @new, (blessed $self)->new(
      mode_array => [ @spl ],
    )
  }

  @new
}

sub mode_sets_matching {
  my ($self, $mode) = @_;
  grep {;
    $_->[1] eq $mode
  } @{ $self->mode_array }
}

sub shift {
  my ($self) = @_;
  shift @{ $self->mode_array }
}

sub BUILD {
  my ($self) = @_;
  confess
    "Expected to be constructed with either a mode_string or mode_array"
    unless $self->has_mode_array or $self->has_mode_string;
}


1;
