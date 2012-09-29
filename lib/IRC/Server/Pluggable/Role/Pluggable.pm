package IRC::Server::Pluggable::Role::Pluggable;

## Based largely on Object::Pluggable:
##  http://www.metacpan.org/dist/Object-Pluggable

use Moo::Role;

use Carp;
use strictures 1;

use IRC::Server::Pluggable qw/
  Constants
  Types
/;

use Scalar::Util 'blessed';

use Try::Tiny;

###
use namespace::clean -except => 'meta';


## FIXME move event_prefix / register_prefix here from Emitter

has '_pluggable_opts' => (
  is  => 'ro',
  isa => HashRef,
  default => sub {
    {
      reg_prefix => 'plugin_',
      ev_prefix  => 'pluggable_',
      types      => {
        PROCESS => 'P',
        NOTIFY  => 'N',
      },
    },
  },
);

has '_pluggable_loaded' => (
  is      => 'ro',
  isa     => HashRef,
  default => sub {
    ALIAS  => {},  ## Objs keyed on aliases
    OBJ    => {},  ## Aliases keyed on obj
    HANDLE => {},  ## Type/event map hashes keyed on obj
  },
);

has '_pluggable_pipeline' => (
  is      => 'ro',
  isa     => ArrayRef,
  default => sub { [] },
);


### Process methods.
sub _pluggable_event {
  my ($self) = @_;
  warn
   "_pluggable_event apparently not implemented in consumer ",
   ref $self, "\n"
}

sub _pluggable_init {
  my ($self, %params) = @_;
  $params{lc $_} = delete $params{$_} for keys %params;

  $self->_pluggable_opts->{reg_prefix} = $params{reg_prefix}
    if defined $params{reg_prefix};

  $self->_pluggable_opts->{ev_prefix} = $params{event_prefix}
    if defined $params{event_prefix};

  if (defined $params{types}) {
    if (ref $params{types} eq 'ARRAY') {
      $self->_pluggable_opts->{types} = {
        map { $_ => $_ } @{ $params{types} }
      };
    } elsif (ref $params{types} eq 'HASH') {
      $self->_pluggable_opts->{types} = $params{types}
    } else {
      confess "Expected types to be an ARRAY or HASH"
    }
  }

  $self
}

sub _pluggable_destroy {
  my ($self) = @_;
  $self->plugin_del( $_ ) for $self->plugin_alias_list;
}

sub _pluggable_process {
  my ($self, $type, $event, $args) = @_;

  unless (defined $type && defined $event) {
    confess "Expected at least a type and event"
  }

  $event = lc $event;
  my $prefix = $self->_pluggable_opts->{ev_prefix};
  $event =~ s/^\Q$prefix\E//;

  my $type_prefix = $self->_pluggable_opts->{types}->{$type};
  my $meth = join '_', $type_prefix, $event;

  my $retval   = EAT_NONE;
  my $self_ret = $retval;

  my @extra;

  local $@;

  if ( $self->can($meth) ) {
    ## Dispatch to ourself
    eval { $self_ret = $self->$meth($self, \(@$args), \@extra) };
    $self->__plugin_process_chk($self, $meth, $self_ret);
  } elsif ( $self->can('_default') ) {
    ## Dispatch to _default
    eval { $self_ret = $self->_default($self, $meth, \(@$args), \@extra) };
    $self->__plugin_process_chk($self, '_default', $self_ret);
  }

  if      (! defined $self_ret) {
    $self_ret = EAT_NONE
  } elsif ($self_ret == EAT_PLUGIN ) {
    return $retval
  } elsif ($self_ret == EAT_CLIENT ) {
    $retval = EAT_ALL
  } elsif ($self_ret == EAT_ALL ) {
    return EAT_ALL
  }

  if (@extra) {
    push @$args, @extra;
    @extra = ();
  }

  PLUG: for my $thisplug (@{ $self->_pluggable_pipeline }) {
    my $handlers = $self->_pluggable_loaded->{HANDLE}->{$thisplug} || {};

    next PLUG if $self eq $thisplug
      or  not defined $handlers->{$type}->{$event}
      and not defined $handlers->{$type}->{all};

    my $plug_ret   = EAT_NONE;
    my $this_alias = ($self->plugin_get($thisplug))[1];

    if      ( $thisplug->can($meth) ) {
      eval { $plug_ret = $thisplug->$meth($self, \(@$args), \@extra) };
      $self->__plugin_process_chk($self, $meth, $plug_ret, $this_alias);
    } elsif ( $thisplug->can('_default') ) {
      eval { $plug_ret = $thisplug->$meth($self, \(@$args), \@extra) };
      $self->__plugin_process_chk($self, '_default', $plug_ret, $this_alias);
    }

    if (! defined $plug_ret) {
      $plug_ret = EAT_NONE
    } elsif ($plug_ret == EAT_PLUGIN) {
      return $retval
    } elsif ($plug_ret == EAT_CLIENT) {
      $retval = EAT_ALL
    } elsif ($plug_ret == EAT_ALL) {
      return EAT_ALL
    }

    if (@extra) {
      push @$args, @extra;
      @extra = ();
    }

  }  ## PLUG

  $retval
}

sub __plugin_process_chk {
  my ($self, $obj, $meth, $retval, $src) = @_;
  $src = defined $src ? "plugin '$src'" : "self" ;

  if ($@) {
    chomp $@;
    my $err = "$meth call on $src failed: $@";

    warn "$err\n";

    $self->_pluggable_event(
      $self->_pluggable_opts->{ev_prefix} . "plugin_error",
      $err,
      ( $obj == $self ? ($obj, $src) : () ),
    );

    return
  }

  if (not defined $retval ||
   (
        $retval != EAT_NONE
     && $retval != EAT_PLUGIN
     && $retval != EAT_CLIENT
     && $retval != EAT_ALL
   ) ) {

    my $err = "$meth call on $src did not return a valid EAT_ constant";

    warn "$err\n";

    $self->_pluggable_event(
      $self->_pluggable_opts->{ev_prefix} . "plugin_error",
      $err,
      ( $obj == $self ? ($obj, $src) : () ),
    );

    return
  }

  1
}

sub plugin_add {
  my ($self, $alias, $plugin, @args) = @_;

  confess "Expected a plugin alias and object"
    unless defined $alias and blessed $plugin;

  $self->plugin_pipe_push($alias, $plugin, @args)
}

sub plugin_del {
  my ($self, $alias_or_plug, @args) = @_;

  confess "Expected a plugin alias"
    unless defined $alias_or_plug;

  scalar( $self->plugin_pipe_remove($alias_or_plug, @args) )
}

sub plugin_get {
  my ($self, $item) = @_;

  confess "Expected a plugin alias or object"
    unless defined $item;

  my ($item_alias, $item_plug) = $self->_get_plug($item);

  unless (defined $item_plug) {
    $@ = "No such plugin: $item_alias";
    return
  }

  wantarray ? ($item_plug, $item_alias) : $item_plug
}

sub plugin_alias_list {
  my ($self) = @_;
  keys %{ $self->_pluggable_loaded->{ALIAS} }
}

sub plugin_register {
  my ($self, $plugin, $type, @events) = @_;

  if (!grep { $_ eq $type } keys %{ $self->_pluggable_opts->{types} }) {
    carp "Cannot register; event type $type not supported";
    return
  }

  unless (@events) {
    carp
      "Expected a plugin object, a type, and a list of events";
    return
  }

  unless (blessed $plugin) {
    carp "Expected a blessed plugin object";
    return
  }

  my $handles
    = $self->_pluggable_loaded->{HANDLE}->{$plugin}->{$type} //= {};

  for my $ev (@events) {
    if (ref $ev eq 'ARRAY') {
      $handles->{lc $_} = 1 for @$ev;
    } else {
      $handles->{lc $ev} = 1;
    }
  }

  1
}

sub plugin_unregister {
  my ($self, $plugin, $type, @events) = @_;

  if (!grep { $_ eq $type } keys %{ $self->_pluggable_opts->{types} }) {
    carp "Cannot unregister; event type $type not supported";
    return
  }

  unless (blessed $plugin && defined $type) {
    carp
      "Expected a blessed plugin obj, event type, and events to unregister";
    return
  }

  unless (@events) {
    carp "No events specified; did you mean to plugin_del instead?";
    return
  }

  my $handles
   = $self->_pluggable_loaded->{HANDLE}->{$plugin}->{$type} || {};

  for my $ev (@events) {

    if (ref $ev eq 'ARRAY') {
      for my $this_ev (map { lc } @$ev) {
        unless (delete $handles->{$this_ev}) {
          carp "Nonexistant event $this_ev cannot be unregistered";
        }
      }
    } else {
      $ev = lc $ev;
      unless (delete $handles->{$ev}) {
        carp "Nonexistant event $ev cannot be unregistered";
      }
    }

  }

  1
}


### Pipeline methods.

sub plugin_push {
  my ($self, $alias, $plug, @args) = @_;

  if (my $existing = $self->_plugin_by_alias($alias) ) {
    $@ = "Already have plugin $alias : $existing";
    return
  }

  return unless $self->_plug_pipe_register($alias, $plug, @args);

  push @{ $self->_pluggable_pipeline }, $plug;

  scalar @{ $self->_pluggable_pipeline }
}

sub plugin_pipe_pop {
  my ($self, @args) = @_;

  return unless @{ $self->_pluggable_pipeline };

  my $plug  = pop @{ $self->_pluggable_pipeline };
  my $alias = $self->_plugin_by_ref($plug);

  $self->_plug_pipe_unregister($alias, $plug, @args);

  wantarray ? ($plug, $alias) : $plug
}

sub plugin_pipe_unshift {
  my ($self, $alias, $plug, @args) = @_;

  if (my $existing = $self->_plugin_by_alias($alias) ) {
    $@ = "Already have plugin $alias : $existing";
    return
  }

  return unless $self->_plug_pipe_register($alias, $plug, @args);

  unshift @{ $self->_pluggable_pipeline }, $plug;

  scalar @{ $self->_pluggable_pipeline }
}

sub plugin_pipe_shift {
  my ($self, @args) = @_;

  return unless @{ $self->_pluggable_pipeline };

  my $plug = shift @{ $self->_pluggable_pipeline };
  my $alias = $self->_plugin_by_ref($plug);

  $self->_plug_pipe_unregister($alias, $plug, @args);

  wantarray ? ($plug, $alias) : $plug
}

sub plugin_pipe_replace {
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

  $self->_plug_pipe_unregister( $old_alias, $old_plug, @unreg_args );

  my ($new_alias, $new_plug) = @params{'alias','plugin'};

  return unless $self->_plug_pipe_register( $new_alias, $new_plug,
    (
      ref $params{register_args} eq 'ARRAY' ?
        @{ $params{register_args} } : ()
    ),
  );

  for my $thisplug (@{ $self->_pluggable_pipeline }) {
    if ($thisplug == $old_plug) {
      $thisplug = $params{plugin};
      last
    }
  }
}

sub plugin_pipe_remove {
  my ($self, $old, @unreg_args) = @_;

  my ($old_alias, $old_plug) = $self->_get_plug($old);

  unless (defined $old_plug) {
    $@ = "No such plugin: $old_alias";
    return
  }

  my $idx = 0;
  for my $thisplug (@{ $self->_pluggable_pipeline }) {
    if ($thisplug == $old_plug) {
      splice @{ $self->_pluggable_pipeline }, $idx, 1;
      last
    }
    ++$idx;
  }

  $self->_plug_pipe_unregister( $old_alias, $old_plug, @unreg_args );

  wantarray ? ($old_plug, $old_alias) : $old_plug
}

sub plugin_pipe_get_index {
  my ($self, $item) = @_;

  my ($item_alias, $item_plug) = $self->_get_plug($item);

  unless (defined $item_plug) {
    $@ = "No such plugin: $item_alias";
    return -1
  }

  my $idx = 0;
  for my $thisplug (@{ $self->_pluggable_pipeline }) {
    return $idx if $thisplug == $item_plug;
    $idx++;
  }

  return -1
}

sub plugin_pipe_insert_before {
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

  if ( my $existing = $self->_plugin_by_alias($params{alias}) ) {
    $@ = "Already have plugin $params{alias} : $existing";
    return
  }

  return unless $self->_plug_pipe_register($params{alias}, $params{plugin},
    (
      ref $params{register_args} eq 'ARRAY' ?
        @{ $params{register_args} } : ()
    )
  );

  my $idx = 0;
  for my $thisplug (@{ $self->_pluggable_pipeline }) {
    if ($thisplug == $prev_plug) {
      splice @{ $self->_pluggable_pipeline }, $idx, 0, $params{plugin};
      last
    }
    $idx++;
  }

  1
}

sub plugin_pipe_insert_after {
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

  if ( my $existing = $self->_plugin_by_alias($params{alias}) ) {
    $@ = "Already have plugin $params{alias} : $existing";
    return
  }

  return unless $self->_plug_pipe_register($params{alias}, $params{plugin},
    (
      ref $params{register_args} eq 'ARRAY' ?
        @{ $params{register_args} } : ()
    ),
  );

  my $idx = 0;
  for my $thisplug (@{ $self->_pluggable_pipeline }) {
    if ($thisplug == $next_plug) {
      splice @{ $self->_pluggable_pipeline }, $idx+1, 0, $params{plugin};
      last
    }
    $idx++;
  }

  1
}

sub plugin_pipe_bump_up {
  my ($self, $item, $delta) = @_;

  my $idx = $self->plugin_pipe_get_index($item);
  return -1 unless $idx >= 0;

  my $pos = $idx - ($delta || 1);

  unless ($pos >= 0) {
    carp "Negative position ($idx - $delta is $pos), bumping to head"
  }

  splice @{ $self->_pluggable_pipeline }, $pos, 0,
    splice @{ $self->_pluggable_pipeline }, $idx, 1;

  $pos
}

sub plugin_pipe_bump_down {
  my ($self, $item, $delta) = @_;

  my $idx = $self->plugin_pipe_get_index($item);
  return -1 unless $idx >= 0;

  my $pos = $idx + ($delta || 1);

  if ($pos >= @{ $self->_pluggable_pipeline }) {
    carp "Cannot bump below end of pipeline, bumping to end"
  }

  splice @{ $self->_pluggable_pipeline }, $pos, 0,
    splice @{ $self->_pluggable_pipeline }, $idx, 1;

  $pos
}

sub _plug_pipe_register {
  my ($self, $new_alias, $new_plug, @args) = @_;

  my ($retval, $err);
  my $meth = $self->_pluggable_opts->{reg_prefix} . "register" ;

  try {
    $retval = $new_plug->$meth( $self, @args )
  } catch {
    chomp;
    $err = "$meth call on '$new_alias' failed: $_";
  };

  unless ($retval) {
    $err = "$meth call on '$new_alias' returned false";
  }

  if ($err) {
    $self->__plug_pipe_handle_err( $err, $new_plug, $new_alias );
    return
  }

  $self->_pluggable_loaded->{ALIAS}->{$new_alias} = $new_plug;
  $self->_pluggable_loaded->{OBJ}->{$new_plug}    = $new_alias;

  $self->_pluggable_event(
    $self->_pluggable_opts->{ev_prefix} . "plugin_add",
    $new_alias,
    $new_plug
  );

  $retval
}

sub _plug_pipe_unregister {
  my ($self, $old_alias, $old_plug, @args) = @_;

  my ($retval, $err);
  my $meth = $self->_pluggable_opts->{reg_prefix} . "unregister" ;

  try {
    $retval = $old_plug->$meth( $self, @args )
  } catch {
    chomp;
    $err = "$meth call on '$old_alias' failed: $_";
  };

  unless ($retval) {
    $err = "$meth called on '$old_alias' returned false";
  }

  if ($err) {
    $self->__plug_pipe_handle_err( $err, $old_plug, $old_alias );
  }

  delete $self->_pluggable_loaded->{ALIAS}->{$old_alias};
  delete $self->_pluggable_loaded->{OBJ}->{$old_plug};
  delete $self->_pluggable_loaded->{HANDLE}->{$old_plug};

  $self->_pluggable_event(
    $self->_pluggable_opts->{ev_prefix} . "plugin_del",
    $old_alias,
    $old_plug
  );

  $retval
}

sub __plug_pipe_handle_err {
  my ($self, $err, $plugin, $alias) = @_;

  warn "$err\n";

  $self->_pluggable_event(
    $self->_pluggable_opts->{ev_prefix} . "plugin_error",
    $err,
    $plugin,
    $alias
  );
}

sub _plugin_by_alias {
  my ($self, $item) = @_;

  $self->_pluggable_loaded->{ALIAS}->{$item}
}

sub _plugin_by_ref {
  my ($self, $item) = @_;

  $self->_pluggable_loaded->{OBJ}->{$item}
}

sub _get_plug {
  my ($self, $item) = @_;

  my ($item_alias, $item_plug) = blessed $item ?
    ( $self->_plugin_by_ref($item), $item )
    : ( $item, $self->_plugin_by_alias($item) ) ;

  wantarray ? ($item_alias, $item_plug) : $item_plug
}


1;
