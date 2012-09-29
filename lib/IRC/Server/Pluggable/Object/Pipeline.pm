package IRC::Server::Pluggable::Object::Pipeline;

## A Moo-ish Object::Pluggable::Pipeline.
## See http://www.metacpan.org/dist/Object-Pluggable

use Carp;

use Moo::Role;
use strictures 1;

use IRC::Server::Pluggable::Types;

use Scalar::Util 'blessed';

use namespace::clean -except => 'meta';

has '_plugin_by_alias' => (
  lazy    => 1,
  is      => 'rw',
  isa     => HashRef,
  default => sub { {} },
);

has '_plugin_by_ref' => (
  lazy    => 1,
  is      => 'rw',
  isa     => HashRef,
  default => sub { {} },
);

has '_pipeline' => (
  lazy    => 1,
  is      => 'rw',
  isa     => ArrayRef,
  default => sub { [] },
);

sub _get_plug {
  my ($self, $item) = @_;

  my ($item_alias, $item_plug) = blessed $item ?
    ( $self->_plugins_by_ref($item), $item )
    : ( $item, $self->_plugins_by_alias($item) ) ;

  wantarray ? ($item_alias, $item_plug) : $item_plug
}

sub push {
  my ($self, $alias, $plug, @args) = @_;

  if (my $existing = $self->_plugins_by_alias->{$alias}) {
    $@ = "Already have plugin $alias : $existing";
    return
  }

  return unless $self->_register($alias, $plug, @args);

  push @{ $self->_pipeline }, $plug;

  scalar @{ $self->_pipeline }
}

sub pop {
  my ($self, @args) = @_;

  return unless @{ $self->_pipeline };

  my $plug  = pop @{ $self->_pipeline };
  my $alias = $self->_plugins_by_ref->{$plug};

  $self->_unregister($alias, $plug, @args);

  wantarray ? ($plug, $alias) : $plug
}

sub unshift {
  my ($self, $alias, $plug, @args) = @_;

  if (my $existing = $self->_plugins_by_alias->{$alias}) {
    $@ = "Already have plugin $alias : ".$self->_plugins_by_alias->{$alias};
    return
  }

  return unless $self->_register($alias, $plug, @args);

  unshift @{ $self->_pipeline }, $plug;

  scalar @{ $self->_pipeline }
}

sub shift {
  my ($self, @args) = @_;

  return unless @{ $self->_pipeline };

  my $plug = shift @{ $self->_pipeline };
  my $alias = $self->_plugins_by_ref->{$plug};

  $self->_unregister($alias, $plug, @args);

  wantarray ? ($plug, $alias) : $plug
}

sub replace {
  my ($self, %params) = @_;
  $params{lc $_} = delete $params{$_} for keys %params;

  ## ->replace(
  ##   old    => $obj || $alias,
  ##   alias  => $newalias,
  ##   plugin => $newplug,
  ## # optional:
  ##   unregister_args => ARRAY
  ##   register_args   => ARRAY
  ## )

  for (qw/old alias plugin/) {
    confess "Missing required param $_"
      unless defined $params{$_}
  }

  my ($old_alias, $old_plug) = $self->_get_plug( $params{old} );

  unless (defined $old_plug) {
    $@ = "No such plugin: $old_alias";
    return
  }

  my @unreg_args = ref $params{unregister_args} eq 'ARRAY' ?
    @{ $params{unregister_args} } : () ;

  $self->_unregister( $old_alias, $old_plug, @unreg_args );

  my ($new_alias, $new_plug) = @params{'alias','plugin'};

  return unless $self->_register( $new_alias, $new_plug,
    (
      ref $params{register_args} eq 'ARRAY' ?
        @{ $params{register_args} } : ()
    ),
  );

  for my $thisplug (@{ $self->_pipeline }) {
    if ($thisplug == $old_plug) {
      $thisplug = $params{plugin};
      last
    }
  }
}

sub remove {
  my ($self, $old, @unreg_args) = @_;

  my ($old_alias, $old_plug) = $self->_get_plug($old);

  unless (defined $old_plug) {
    $@ = "No such plugin: $old_alias";
    return
  }

  my $idx = 0;
  for my $thisplug (@{ $self->_pipeline }) {
    if ($thisplug == $old_plug) {
      splice @{ $self->_pipeline }, $idx, 1;
      last
    }
    ++$idx;
  }

  $self->_unregister( $old_alias, $old_plug, @unreg_args );

  wantarray ? ($old_plug, $old_alias) : $old_plug
}

sub get {
  my ($self, $item) = @_;

  my ($item_alias, $item_plug) = $self->_get_plug($item);

  unless (defined $item_plug) {
    $@ = "No such plugin: $item_alias";
    return
  }

  wantarray ? ($item_plug, $item_alias) : $item_plug
}

sub get_index {
  my ($self, $item) = @_;

  my ($item_alias, $item_plug) = $self->_get_plug($item);

  unless (defined $item_plug) {
    $@ = "No such plugin: $item_alias";
    return -1
  }

  my $idx = 0;
  for my $thisplug (@{ $self->_pipeline }) {
    return $idx if $thisplug == $item_plug;
    $idx++;
  }

  return -1
}

sub insert_before {
  my ($self, %params) = @_;
  $params{lc $_} = delete $params{$_} for keys %params;
  ## ->insert_before(
  ##   before =>
  ##   alias  =>
  ##   plugin =>
  ##   register_args =>
  ## );

  for (qw/before alias plugin/) {
    confess "Missing required param $_"
      unless defined $params{$_}
  }

  my ($prev_alias, $prev_plug) = $self->_get_plug( $params{before} );

  unless (defined $prev_plug) {
    $@ = "No such plugin: $prev_alias";
    return
  }

  if ( my $existing = $self->_plugins_by_alias->{ $params{alias} } ) {
    $@ = "Already have plugin $params{alias} : $existing";
    return
  }

  return unless $self->_register($params{alias}, $params{plugin},
    (
      ref $params{register_args} eq 'ARRAY' ?
        @{ $params{register_args} } : ()
    )
  );

  my $idx = 0;
  for my $thisplug (@{ $self->_pipeline }) {
    if ($thisplug == $prev_plug) {
      splice @{ $self->_pipeline }, $idx, 0, $params{plugin};
      last
    }
    $idx++;
  }

  1
}

sub insert_after {
  my ($self, %params) = @_;
  $params{lc $_} = delete $params{$_} for keys %params;

  for (qw/after alias plugin/) {
    confess "Missing required param $_"
      unless defined $params{$_}
  }

  my ($next_alias, $next_plug) = $self->_get_plug( $params{after} );

  unless (defined $next_plug) {
    $@ = "No such plugin: $next_alias";
    return
  }

  if ( my $existing = $self->_plugins_by_alias->{ $params{alias} } ) {
    $@ = "Already have plugin $params{alias} : $existing";
    return
  }

  return unless $self->_register($params{alias}, $params{plugin},
    (
      ref $params{register_args} eq 'ARRAY' ?
        @{ $params{register_args} } : ()
    ),
  );

  my $idx = 0;
  for my $thisplug (@{ $self->_pipeline }) {
    if ($thisplug == $next_plug) {
      splice @{ $self->_pipeline } }, $idx+1, 0, $params{plugin};
      last
    }
    $idx++;
  }

  1
}

sub bump_up {
  my ($self, $item, $delta) = @_;

  my $idx = $self->get_index($item);
  return -1 unless $idx >= 0;

  my $pos = $idx - ($delta || 1);

  unless ($pos >= 0) {
    carp "Negative position ($idx - $delta is $pos), bumping to head"
  }

  splice @{ $self->_pipeline }, $pos, 0,
    splice @{ $self->_pipeline }, $idx, 1;

  $pos
}

sub bump_down {
  my ($self, $item, $delta) = @_;

  my $idx = $self->get_index($item);
  return -1 unless $idx >= 0;

  my $pos = $idx + ($delta || 1);

  if ($pos >= @{ $self->_pipeline }) {
    carp "Cannot bump below end of pipeline, bumping to end"
  }

  splice @{ $self->_pipeline }, $pos, 0,
    splice @{ $self->_pipeline }, $idx, 1;

  $pos
}

sub _register {

}

sub _unregister {

}

sub _handle_error {

}

1;
