package IRC::Server::Pluggable::Role::Pluggable;

## Moo::Role for a pluggable object.
## Based largely on Object::Pluggable:
##  http://www.metacpan.org/dist/Object-Pluggable
## Retaining API compat is a plus, but not mandatory, given good reason.

use Moo::Role;

use Carp;
use strictures 1;

use IRC::Server::Pluggable qw/
  Constants
  Types
/;

use Scalar::Util 'blessed';

use Try::Tiny;


use namespace::clean -except => 'meta';


has '_pluggable_opts' => (
  is  => 'ro',
  isa => HashRef,
  default => sub {
    {
      reg_prefix => 'plugin_',
      ev_prefix  => 'plugin_ev_',
      types      => { PROCESS => 'P',  NOTIFY => 'N' },
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
  ## This should be overriden to handle Pluggable events
  ##  ( plugin_{added, removed, error} )
  return
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
        map {
          $_ => $_
        } @{ $params{types} }
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
  ## Some of the tighter code; I'm open to optimization ideas.

  unless (ref $args) {
    ## No explicit 'ARRAY' check to save a string comparison
    confess "Expected a type, event, and (possibly empty) args ARRAY"
  }

  ## Hmm. Should benchmark index+substr against regex, here:
  my $prefix = $self->_pluggable_opts->{ev_prefix};
  $event =~ s/^\Q$prefix\E//;

  my $meth = join( '_',
    (
     $self->_pluggable_opts->{types}->{$type}
       // confess "Cannot _pluggable_process unknown type $type"
    ),
    $event
  );

  my $retval = my $self_ret = EAT_NONE;

  my @extra;

  local $@;

  if      ( $self->can($meth) ) {
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

  my $handle_ref = $self->_pluggable_loaded->{HANDLE};

  PLUG: for my $thisplug (@{ $self->_pluggable_pipeline }) {

    next PLUG
      if $self == $thisplug
      or not exists $handle_ref->{$thisplug}->{$type}
      or (  ## Parens for readability. I'm not sorry.
       not exists $handle_ref->{$thisplug}->{$type}->{$event}
        and not exists $handle_ref->{$thisplug}->{$type}->{all}
      );

    my $plug_ret   = EAT_NONE;
    my $this_alias = ($self->plugin_get($thisplug))[1];

    if      ( $thisplug->can($meth) ) {
      eval { $plug_ret = $thisplug->$meth($self, \(@$args), \@extra) };
      $self->__plugin_process_chk($self, $meth, $plug_ret, $this_alias);
    } elsif ( $thisplug->can('_default') ) {
      eval { $plug_ret = $thisplug->$meth($self, \(@$args), \@extra) };
      $self->__plugin_process_chk($self, '_default', $plug_ret, $this_alias);
    }

    if      (! defined $plug_ret) {
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

sub plugin_replace {
  my ($self, %params) = @_;
  $params{lc $_} = delete $params{$_} for keys %params;

  ## ->plugin_replace(
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


### Pipeline methods.

sub plugin_pipe_push {
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
    $self->_pluggable_opts->{ev_prefix} . "plugin_added",
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
    $self->_pluggable_opts->{ev_prefix} . "plugin_removed",
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

=pod

=head1 NAME

IRC::Server::Pluggable::Role::Pluggable - Pluggable object role

=head1 SYNOPSIS

  package MyPluggable;
  use Moo;

  with 'IRC::Server::Pluggable::Role::Pluggable';

FIXME examples

=head1 DESCRIPTION

A L<Moo::Role> for turning instances of your class into pluggable objects.

Consumers of this role gain a plugin pipeline and methods to manipulate it,
as well as a flexible dispatch system (see L</_pluggable_process>).

This implementation is originally based on L<Object::Pluggable>.

=head2 Initialization

=head3 _pluggable_init

  $self->_pluggable_init(
    ## Prefix for registration events.
    ## Defaults to 'plugin_' ('plugin_register' / 'plugin_unregister')
    reg_prefix   => 'plugin_',

    ## Prefix for dispatched internal events
    ##  (add, del, error, register, unregister ...)
    ## Defaults to 'plugin_ev_'
    event_prefix => 'plugin_ev_',

    ## Map type names to prefixes.
    ## Event types are arbitrary.
    ## Prefix is prepended when dispathing events of a particular type.
    ## Defaults to: { NOTIFY => 'N', PROCESS => 'P' }
    types => [
      NOTIFY  => 'N',
      PROCESS => 'P',
    ];
  );

A consumer should call _pluggable_init to set up C<_pluggable_opts> 
appropriately prior to loading plugins.

=head3 _pluggable_destroy

  $self->_pluggable_destroy;

Shuts down the plugin pipeline, unregistering all known plugins.

=head3 _pluggable_event

  sub _pluggable_event {
    my ($self, $event) = @_;
    ## ... dispatch out with @_ perhaps
  }

C<_pluggable_event> is called for internal notifications.

It should be overriden in your consuming class to do something useful with 
the dispatched event (and any other arguments passed in).

The C<$event> passed will be prefixed with the configured B<event_prefix>.

Also see L</Internal events>

=head2 Registration

=head3 plugin_register

  $self->plugin_register( $plugin_obj, $type, @events );

Registers a plugin object to receive C<@events> of type C<$type>.

This is frequently called from within the plugin's registration handler:

  ## In MyPlugin
  sub plugin_register {
    my ($self, $manager) = @_;
    $manager->plugin_register( $self, 'NOTIFY', 'all' );
  }

Register for 'all' to receive all events.

=head3 plugin_unregister

The unregister counterpart to L</plugin_register>; stops delivering
specified events to a plugin.

Carries the same arguments as L</plugin_register>.

=head2 Dispatch

=head3 _pluggable_process

  my $eat = $self->_pluggable_process( $type, $event, \@args );
  return 1 if $eat == EAT_ALL;

The C<_pluggable_process> method handles dispatching.

If C<$event> is prefixed with our event prefix (see L</_pluggable_init>),
the prefix is stripped prior to dispatch (to be replaced with a type 
prefix matching the specified C<$type>).

Arguments should be passed in as an ARRAY. During dispatch, references to 
the arguments are passed to subs following automatically-prepended objects 
belonging to the plugin and the pluggable caller, respectively:

  my @args = qw/baz bar/;
  $self->_pluggable_process( 'NOTIFY', 'foo', \@args );

  ## In a plugin:
  sub N_foo {
    my ($self, $manager) = splice @_, 0, 2;
    ## Dereferenced expected scalars:
    my $baz = ${ $_[0] };
    my $bar = ${ $_[1] };
  }

This allows for argument modification as an event is passed along the 
pipeline.

Dispatch process for C<$event> 'foo' of C<$type> 'NOTIFY':

  - Prepend the known prefix for the specified type, and '_'
    'foo' -> 'N_foo'
  - Attempt to dispatch to $self->N_foo()
  - If no such method, attempt to dispatch to $self->_default()
  - If the event was not eaten (see below), dispatch to plugins

"Eaten" means a handler returned a EAT_* constant from 
L<IRC::Server::Pluggable::Constants> indicating that the event's lifetime 
should terminate. See L<IRC::Server::Pluggable::Role::Emitter> for more on 
how EAT values interact with higher layers.

Specifically:

B<If our consuming class provides a method or '_default' that returns:>

    EAT_ALL:    skip plugin pipeline, return EAT_ALL
    EAT_PLUGIN: skip plugin pipeline, return EAT_NONE
    EAT_CLIENT: continue to plugin pipeline
                return EAT_ALL if plugin returns EAT_PLUGIN later
    EAT_NONE:   continue to plugin pipeline

B<If one of our plugins in the pipeline returns:>

    EAT_ALL:    skip further plugins, return EAT_ALL
    EAT_CLIENT: continue to next plugin, set pending EAT_ALL
    EAT_PLUGIN: return EAT_ALL if previous sub returned EAT_CLIENT
                else return EAT_NONE
    EAT_NONE:   continue to next plugin

This functionality from L<Object::Pluggable> provides fine-grained control 
over event lifetime.

=head2 Public Methods

=head3 plugin_add

  $self->plugin_add( $alias, $plugin_obj, @args );

Add a plugin object to the pipeline.

=head3 plugin_del

  $self->plugin_del( $alias_or_plugin_obj, @args );

Remove a plugin from the pipeline.

Takes either a plugin alias or object.

=head3 plugin_get

  my $plug_obj = $self->plugin_get( $alias );
	my ($plug_obj, $plug_alias) = $self->plugin_get( $alias_or_plugin_obj );

In scalar context, returns the plugin object belonging to the specified 
alias.

In list context, returns the object and alias, respectively.

=head3 plugin_alias_list

  my @loaded = $self->plugin_alias_list;

Returns a list of loaded plugin aliases.

=head3 plugin_replace

  $self->plugin_replace(
    old    => $alias_or_plugin_obj,
    alias  => $new_alias,
    plugin => $new_plugin_obj,
    ## Optional:
    register_args   => [ ],
    unregister_args => [ ],
  );

Replace an existing plugin object with a new one.

=head2 Pipeline methods

=head3 plugin_pipe_push

  $self->plugin_pipe_push( $alias, $plugin_obj, @args );

Add a plugin to the end of the pipeline.

(Use L</plugin_add> to load plugins.)

=head3 plugin_pipe_pop

  my $plug = $self->plugin_pipe_pop( @unregister_args );

Pop the last plugin off the pipeline, passing any specified arguments to 
L</plugin_unregister>.

=head3 plugin_pipe_unshift

  $self->plugin_pipe_unshift( $alias, $plugin_obj, @args );

Add a plugin to the beginning of the pipeline.

=head3 plugin_pipe_shift

  $self->plugin_pipe_shift( @unregister_args );

Shift the first plugin off the pipeline, passing any specified args to 
L</plugin_unregister>.

=head3 plugin_pipe_get_index

  my $idx = $self->plugin_pipe_get_index( $alias_or_plugin_obj );
  if ($idx < 0) {
    ## Plugin doesn't exist
  }

Returns the position of the specified plugin in the pipeline, or -1 if it 
cannot be located.

=head3 plugin_pipe_insert_after

  $self->plugin_pipe_insert_after(
    after  => $alias_or_plugin_obj,
    alias  => $new_alias,
    plugin => $new_plugin_obj,
    ## Optional:
    register_args => [ ],
  );

Add a plugin to the pipeline after the specified previously-existing alias 
or plugin object.

=head3 plugin_pipe_insert_before

  $self->plugin_pipe_insert_before(
    before => $alias_or_plugin_obj,
    alias  => $new_alias,
    plugin => $new_plugin_obj,
    ## Optional:
    register_args => [ ],
  );

Similar to L</plugin_pipe_insert_after>, but insert before the specified 
previously-existing plugin, not after.

=head3 plugin_pipe_bump_up

  $self->plugin_pipe_bump_up( $alias_or_plugin_obj, $count );

Move the specified plugin 'up' C<$count> positions in the pipeline.

=head3 plugin_pipe_bump_down

  $self->plugin_pipe_bump_down( $alias_or_plugin_obj, $count );

Move the specified plugin 'down' C<$count> positions in the pipeline.

=head2 Internal events

=head3 plugin_error

Issued via L</_pluggable_event> when an error occurs.

The first argument is always the error string; if it wasn't our consumer 
class that threw the error, the source object is included as the second 
argument.

=head3 plugin_added

Issued via L</_pluggable_event> when a new plugin is registered.

Arguments are the new plugin alias and object, respectively.

=head3 plugin_removed

Issued via L</_pluggable_event> when a plugin is unregistered.

Arguments are the old plugin alias and object, respectively.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

Based on L<Object::Pluggable> by BINGOS, HINRIK et al.

=cut
