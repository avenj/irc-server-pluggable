package IRC::Server::Pluggable::Role::Emitter;

## Moo::Role adding POE event emission to Role::Pluggable behavior
## Based largely on POE::Component::Syndicator:
##  http://www.metacpan.org/dist/POE-Component-Syndicator

use Moo::Role;

use Carp;
use strictures 1;

use IRC::Server::Pluggable qw/
  Constants
  Types
/;

use POE;

## namespace::clean
use namespace::clean -except => 'meta';


## No reason you couldn't use a different plugin system,
## so long as you provide compat methods and return EAT values:
requires qw/
  _pluggable_init
  _pluggable_destroy
  _pluggable_process
  _pluggable_event
/;

has 'alias' => (
  lazy => 1,
  is   => 'ro',
  isa  => Str,
  predicate => 'has_alias',
  writer    => 'set_alias',
  default   => sub { "$_[0]" },
);

has 'event_prefix' => (
  lazy => 1,
  is   => 'ro',
  isa  => Str,
  predicate => 'has_event_prefix',
  writer    => 'set_event_prefix',
  default   => sub { "emitted_" },
);

has 'object_states' => (
  lazy => 1,
  is   => 'ro',
  isa  => ArrayRef,
  predicate => 'has_object_states',
  writer    => 'set_object_states',
  trigger   => 1,
);

has 'register_prefix' => (
  lazy => 1,
  is   => 'ro',
  isa  => Str,
  predicate => 'has_register_prefix',
  writer    => 'set_register_prefix',
  ## Emitter_register / Emitter_unregister
  default   => sub { "Emitter_" },
);

has 'session_id' => (
  init_arg => undef,
  lazy => 1,
  is   => 'ro',
  isa  => Defined,
  predicate => 'has_session_id',
  writer    => 'set_session_id',
);


has '__emitter_reg_sessions' => (
  ## ->{ $session_id } = { refc => $ref_count, id => $id };
  lazy => 1,
  is   => 'ro',
  isa  => HashRef,
  default => sub { {} },
);

has '__emitter_reg_events' => (
  ## ->{ $event }->{ $session_id } = 1
  lazy => 1,
  is   => 'ro',
  isa  => HashRef,
  default => sub { {} },
);


sub _start_emitter {
  ## Call to spawn Session.
  ##   my $self = $class->new(
  ##     alias           => Emitter session alias
  ##     event_prefix    => Session event prefix (emitted_)
  ##     register_prefix => _register/_unregister prefix (Emitter_)
  ##     object_states   => Extra object_states for Session
  ##   )->_start_emitter();
  my ($self) = @_;

  $self->_pluggable_init(
    event_prefix  => $self->event_prefix,
    reg_prefix    => $self->register_prefix,

    types => {

      ## PROCESS type events are handled synchronously.
      ## Handlers begin with P_*
      PROCESS => 'P',

      ## NOTIFY type events are dispatched asynchronously.
      ## Handlers begin with N_*
      NOTIFY  => 'N',
    },
  );

  POE::Session->create(
    object_states => [

      $self => {
        '_start'           => '_p_emitter_start',
        '_stop'            => '_p_emitter_stop',
        'shutdown_emitter' => '_p_shutdown_emitter',

        'register'    => '_p_emitter_register',
        'subscribe'   => '_p_emitter_register',
        'unregister'  => '_p_emitter_unregister',
        'unsubscribe' => '_p_emitter_unregister',

        '_default'   => '_emitter_default',
      },

      $self => [ qw/
        __emitter_notify

        _emitter_sigdie
      / ],

      (
        $self->has_object_states ? @{ $self->object_states } : ()
      ),

    ],
  );

  $self
}


sub _pluggable_event {
  my $self = shift;

  ## Overriden from Role::Pluggable
  ## Receives plugin_error, plugin_add etc
  ## Redispatch via emit()

  $self->emit( @_ );
}


### Methods.

sub timer {
  my ($self, $time, $event, @args) = @_;

  confess "timer() expected at least a time and event name"
    unless defined $time
    and defined $event;

  my $alarm_id = $poe_kernel->delay_set($event, $time, @args);

  $self->emit( $self->event_prefix . 'timer_set',
    $alarm_id,
    $event,
    @args
  ) if $alarm_id;

  $alarm_id
}

sub timer_del {
  my ($self, $alarm_id) = @_;

  confess "timer_del() expects an alarm ID"
    unless defined $alarm_id;

  if ( my @deleted = $poe_kernel->alarm_remove($alarm_id) ) {
    my ($event, undef, $params) = @deleted;
    $self->emit( $self->event_prefix . 'timer_deleted',
      $alarm_id,
      $event,
      @{$params||[]}
    );
    return $params
  }

  return
}

## yield/call provide post()/call() frontends.
sub yield {
  my ($self, @args) = @_;

  $poe_kernel->post( $self->session_id, @args );

  $self
}

sub call {
  my ($self, @args) = @_;

  $poe_kernel->call( $self->session_id, @args );

  $self
}

sub emit {
  ## Async NOTIFY event dispatch.
  my ($self, $event, @args) = @_;

  $self->yield( '__emitter_notify', $event, @args );

  $self
}

sub emit_now {
  ## Synchronous NOTIFY event dispatch.
  my ($self, $event, @args) = @_;

  $self->call( '__emitter_notify', $event, @args );

  $self
}

sub process {
  my ($self, $event, @args) = @_;
  ## Dispatch PROCESS events.
  ## process() events should _pluggable_process immediately
  ##  and return the EAT value.

  ## Dispatched to P_$event :
  $self->_pluggable_process( 'PROCESS', $event, \@args )
}


sub _trigger_object_states {
  my ($self, $states) = @_;

  confess "object_states() should be an ARRAY or HASH"
    unless ref $states eq 'HASH' or ref $states eq 'ARRAY' ;

  my @disallowed = qw/
    _start
    _stop
    register
    unregister
  /;

  for (my $i=1; $i <= (scalar(@$states) - 1 ); $i+=2 ) {
    my $events = $states->[$i];
    my $evarr = ref $events eq 'ARRAY' ? $events : [ keys %$events ];

    for my $ev (@$evarr) {
      confess "Disallowed handler: $ev"
        if grep { $_ eq $ev } @disallowed;
    }

  }

  $states
}


## Session ref-counting bits.

sub __incr_ses_refc {
  my ($self, $sess_id) = @_;
  ++$self->__emitter_reg_sessions->{$sess_id}->{refc}
}

sub __decr_ses_refc {
  my ($self, $sess_id) = @_;
  --$self->__emitter_reg_sessions->{$sess_id}->{refc};
  $self->__emitter_reg_sessions->{$sess_id}->{refc} = 0
    unless $self->__emitter_reg_sessions->{$sess_id}->{refc} > 0
}

sub __get_ses_refc {
  my ($self, $sess_id) = @_;
  $self->__emitter_reg_sessions->{$sess_id}->{refc}
    if exists $self->__emitter_reg_sessions->{$sess_id}
}

sub __reg_ses_id {
  my ($self, $sess_id) = @_;
  $self->__emitter_reg_sessions->{$sess_id}->{id} = $sess_id
}


sub __emitter_drop_sessions {
  my ($self) = @_;

  for my $id (keys %{ $self->__emitter_reg_sessions }) {
    my $count = $self->__get_ses_refc($id);

    $poe_kernel->refcount_decrement(
      $id, 'Emitter running'
    ) while $count-- > 0;

    delete $self->__emitter_reg_sessions->{$id}
  }

  1
}


## Our Session's handlers:

sub __emitter_notify {
  ## Dispatch a NOTIFY event
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($event, @args) = @_[ARG0 .. $#_];

  my $prefix = $self->event_prefix;

  ## May have event_prefix (such as $prefix.'plugin_error')
  $event =~ s/^\Q$prefix\E//;

  my %sessions;

  for my $regev ('all', $event) {
    if (exists $self->__emitter_reg_events->{$regev}) {
      next unless keys %{ $self->__emitter_reg_events->{$regev} };

      $sessions{$_} = 1
        for values %{ $self->__emitter_reg_events->{$regev} };
    }
  }

  my $meth = $prefix . $event;

  ## Our own session will get ->event_prefix . $event first
  $kernel->call( $_[SESSION], $meth, @args )
    if delete $sessions{ $_[SESSION]->ID };

  ## Dispatched to N_$event after Sessions have been notified:
  my $eat = $self->_pluggable_process( 'NOTIFY', $event, \@args );

  unless ($eat == EAT_ALL) {
    ## Notify registered sessions.
    $kernel->call( $_, $meth, @args )
      for keys %sessions;
  }

  ## Received emitted 'shutdown', drop sessions.
  $self->__emitter_drop_sessions
    if $event eq 'shutdown';
}

sub _p_emitter_start {
  ## _start handler
  my ($kernel, $self)    = @_[KERNEL, OBJECT];
  my ($session, $sender) = @_[SESSION, SENDER];

  $self->set_session_id( $session->ID );

  $kernel->sig('DIE', '_emitter_sigdie' );

  $kernel->alias_set( $self->alias );

  my $s_id = $sender->ID;

  unless ($sender == $kernel) {
    ## Have a parent session.

    ## refcount for this session.
    $kernel->refcount_increment( $s_id, 'Emitter running' );
    $self->__incr_ses_refc( $s_id );
    $self->__reg_ses_id( $s_id );

    ## register parent session for all notification events.
    $self->__emitter_reg_events->{ 'all' }->{ $s_id } = 1;

    ## Detach child session.
    $kernel->detach_myself;
  }

  $self->call( 'emitter_started' );

  $self
}

sub _emitter_default {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($event, $args) = @_[ARG0, ARG1];

  ## Session received an unknown event.
  ## Dispatch it to any appropriate P_$event handlers.

  $self->process( $event, @$args )
    unless $event =~ /^_/
    or $event =~ /^emitter_(?:started|stopped)$/ ;
}

sub _emitter_sigdie {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $exh = $_[ARG1];

  my $event   = $exh->{event};
  my $dest_id = $exh->{dest_session}->ID;
  my $errstr  = $exh->{error_str};

  warn
    "SIG_DIE: Event '$event'  session '$dest_id'\n",
    "  exception: $errstr\n";

  $kernel->sig_handled;
}

sub _p_emitter_stop {
  ## _stop handler
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $self->call( 'emitter_stopped' );
}

sub _shutdown_emitter {
  ## Opposite of _start_emitter
  my $self = shift;

  $self->call( 'shutdown_emitter', @_ );

  1
}

sub _p_shutdown_emitter {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $kernel->alarm_remove_all;

  ## Destroy plugin pipeline.
  $self->_pluggable_destroy;

  ## Notify sessions.
  $self->emit( 'shutdown', @_[ARG0 .. $#_] );

  ## Drop sessions and we're spent.
  $self->__emitter_drop_sessions;
}


## Handlers for listener sessions.
sub _p_emitter_register {
  my ($kernel, $self, $sender) = @_[KERNEL, OBJECT, SENDER];
  my @events = @_[ARG0 .. $#_];

  @events = 'all' unless @events;

  my $s_id = $sender->ID;

  ## Add to our known sessions.
  $self->__reg_ses_id( $s_id );

  for my $event (@events) {
    ## Add session to registered event lists.
    $self->__emitter_reg_events->{$event}->{$s_id} = 1;

    ## Make sure registered session hangs around
    ##  (until _unregister or shutdown)
    $kernel->refcount_increment( $s_id, 'Emitter running' )
      if not $self->__get_ses_refc($s_id)
      and $s_id ne $self->session_id ;

    $self->__incr_ses_refc( $s_id );
  }

  $kernel->post( $s_id, $self->event_prefix . "registered", $self )
}

sub _p_emitter_unregister {
  my ($kernel, $self, $sender) = @_[KERNEL, OBJECT, SENDER];
  my @events = @_[ARG0 .. $#_];

  @events = 'all' unless @events;

  my $s_id = $sender->ID;

  EV: for my $event (@events) {
    unless (delete $self->__emitter_reg_events->{$event}->{$s_id}) {
      ## Possible we should just not give a damn?
      warn "Cannot unregister $event for $s_id -- not registered";
      next EV
    }

    delete $self->__emitter_reg_events->{$event}
      ## No sessions left for this event.
      unless keys %{ $self->__emitter_reg_events->{$event} };

    $self->__decr_ses_refc($s_id);

    unless ($self->__get_ses_refc($s_id)) {
      ## No events left for this session.
      delete $self->__emitter_reg_sessions->{$s_id};

      $kernel->refcount_decrement( $s_id, 'Emitter running' )
        unless $_[SESSION] == $sender;
    }

  } ## EV
}

no warnings 'void';
q[
 <tberman> who wnats to sing a song with me?
 <tberman> its the i hate php song
 * rac adds a stanza to tberman's song about braindead variable scoping
   that just made forums search return a bunch of false positives when
   you search for posts by poster and return by topics
];


=pod

=head1 NAME

IRC::Server::Pluggable::Role::Emitter - POE-enabled Emitter role

=head1 SYNOPSIS

  package My::EventEmitter;

  use Moo;
  with 'IRC::Server::Pluggable::Role::Pluggable';
  with 'IRC::Server::Pluggable::Role::Emitter';

  sub spawn {
    my ($self, %args) = @_;
    $args{lc $_} = delete $args{$_} for keys %args;

    $self->set_object_states(
      [
        $self => [
          ## ... Add some extra handlers ...
        ],

        ## Include any object_states we were instantiated with:
        (
          $self->has_object_states ?
            @{ $self->object_states } : ()
        ),

        ## Maybe include from named arguments:
        (
          ref $args{object_states} eq 'ARRAY' ?
            @{ $args{object_states } : ()
        ),
      ],
    );

    ## Start our Emitter session:
    $self->_start_emitter;
  }

  FIXME

=head1 DESCRIPTION

This is a L<Moo::Role> for a POE-oriented Observer Pattern implementation; 
it is based on L<POE::Component::Syndicator> (which may be better suited
to general purpose use).

Consuming this role gives your class a POE::Session capable of 
emitting events to loaded plugins and registered sessions.

You will need the methods defined by 
L<IRC::Server::Pluggable::Role::Pluggable>. It's common to consume 
Role::Pluggable first:

  package MyEmitter;
  use Moo;
  with 'IRC::Server::Pluggable::Role::Pluggable';
  with 'IRC::Server::Pluggable::Role::Emitter';

...but any compatible plugin system will do, see notes in source.


=head2 Creating an Emitter

L</SYNOPSIS> contains an Emitter that uses B<set_$attrib> methods to
configure itself when C<spawn()> is called; these attribs can, of course,
be set when your Emitter is instantiated instead.

=head3 Attributes

=head4 alias

B<alias> specifies the POE::Kernel alias used for our session; defaults 
to the stringified object.

Set via B<set_alias>

=head4 event_prefix

B<event_prefix> is prepended to notification events before they are
dispatched to registered sessions.

Defaults to I<emitted_>

Set via B<set_event_prefix>

=head4 register_prefix

B<register_prefix> is prepended to 'register' and 'unregister' methods
called on plugins at load time.

Defaults to I<Emitter_>

Set via B<set_register_prefix>

=head4 object_states

B<object_states> is an array reference suitable for passing to
L<POE::Session>; the subclasses own handlers should be added to
B<object_states> prior to calling L</_start_emitter>.

Set via B<set_object_states>

=head4 session_id

B<session_id> is our Emitter L<POE::Session> ID.


=head3 _start_emitter

B<_start_emitter()> should be called on our object to spawn the actual
Emitter L<POE::Session>.


=head2 Registering sessions

=head3 Session event registration

An external L<POE::Session> can register to receive events via asynchronous 
event dispatch by sending a C<register>:

  $poe_kernel->post( $emitter->session_id,
    'register',
    @events
  );

Registered sessions are consumers; they cannot modify event arguments in 
any meaningful way, and will receive arguments as-normal (in @_[ARG0 .. 
$#_] like any other POE state).

=head3 Session event unregistration

FIXME

=head2 Receiving events

FIXME

=head3 Events delivered to this session

The Emitter's Session provides a '_default' handler that redispatches 
unknown POE-delivered events to L</process> (except for events prefixed 
with '_', which are reserved).

As a side-effect, registering the 'self' Session for some events (or 'all') 
will cause unhandled L</NOTIFY events> to be redispatched as L</PROCESS 
events>.

To change this behavior, override the method '_emitter_default' in your 
class:

  use Moo;
  with 'IRC::Server::Pluggable::Role::Emitter';
  around '_emitter_default' => sub {
    ## Drop unknown events on the floor, for example:
    return
  };

=head2 EAT values

FIXME summarize our behavior, link back to Role::Pluggable details

=head3 NOTIFY events

B<NOTIFY> events are intended to be dispatched asynchronously to our own
session, the registered plugin pipeline, and registered sessions,
respectively.

See L</emit> for complete details.

=head3 PROCESS events

B<PROCESS> events are intended to be processed by the plugin pipeline
immediately; these are intended for message processing and similar
synchronous action handled by plugins.

Handlers for B<PROCESS> events are prefixed with C<P_>

See L</process>.


=head2 Sending events

=head3 emit

  $self->emit( $event, @args );

B<emit()> dispatches L</"NOTIFY events"> -- these events are dispatched
first to our own session (with L</event_prefix> prepended), then the
registered plugin pipeline (with C<N_> prepended), then registered
sessions (with L</event_prefix> prepended):

  With default event_prefix:

  $self->emit( 'my_event', @args )

    -> Dispatched to own session as 'emitted_my_event'
    --> Dispatched to plugin pipeline as 'N_my_event'
    ---> Dispatched to registered sessions as 'emitted_my_event'

=head3 emit_now

  $self->emit_now( $event, @args );

B<emit_now()> synchronously dispatches L</"NOTIFY events"> -- see
L</emit>.

=head3 process

  $self->process( $event, @args );

B<process()> calls registered plugin handlers for L</"PROCESS events">
immediately; these are not dispatched to sessions.

See L<IRC::Server::Pluggable::Role::Pluggable> for details on pluggable 
event dispatch.

=head3 timer

FIXME

=head3 timer_del

FIXME

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

Based largely on L<POE::Component::Syndicator>-0.06 -- I needed something
Moo-ish.

=cut

