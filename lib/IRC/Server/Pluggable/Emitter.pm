package IRC::Server::Pluggable::Emitter;
our $VERSION;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use Object::Pluggable::Constants qw/:ALL/;

extends 'Object::Pluggable';

use IRC::Server::Pluggable qw/
  Emitter::Session

  Types
/;

## FIXME support Session registration also
##  Sessions can only receive notifications

has 'alias' => (
  lazy => 1,
  is   => 'ro',
  isa  => Str,

  predicate => 'has_alias',
  
  default => sub { "$_[0]" },
);

has 'event_prefix' => (
  lazy => 1,
  is   => 'ro',
  isa  => Str,
  writer  => 'set_event_prefix',
  default => sub { "Emitter_ev_" },
);

has 'session_id' => (
  lazy => 1,
  is   => 'ro',
  isa  => Defined,  
  predicate => 'has_session_id',
  writer    => 'set_session_id',
);

has 'object_states' => (
  lazy => 1,
  is  => 'ro',
  isa => ArrayRef,
  predicate => 'has_object_states',
  writer    => 'set_object_states',
  trigger   => 1,
);

## ->{ $session_id } = { refc => $ref_count, id => $id };
has '_reg_sessions' => (
  lazy => 1,
  is  => 'ro',
  isa => HashRef,
  default => sub { {} },
);

## ->{ $event }->{ $session_id } = 1
has '_reg_events' => (
  lazy => 1,
  is  => 'ro',
  isa => HashRef,
  default => sub { {} },
);


sub import {
  my $self = shift;
  
  my $pkg = caller();
  
  {
    no strict 'refs';
    for (qw/ EAT_NONE EAT_CLIENT EAT_PLUGIN EAT_ALL /) {
      *{ $pkg .'::' .$_ } 
        = *{ 'Object::Pluggable::Constants::PLUGIN_' .$_ }
    }
  }    
}

sub _spawn_emitter {
  ## Call me from subclass to set up our Emitter.
  my ($self, %args) = @_;
  $args{lc $_} = delete $args{$_} for keys %args;

  ## FIXME
  ##  process args
  ##  call _pluggable_init
  ##  spawn our Session
  $self->_pluggable_init(
    prefix     => $self->event_prefix,
    reg_prefix => 'Emitter',    ## Emitter_register()
    types => {
      ## PROCESS type events are handled synchronously.
      ## Handlers begin with P_*
      'PROCESS => 'P',
      ## NOTIFY type events are dispatched asynchronously.
      ## Handlers begin with N_*
      'NOTIFY' => 'N',
    },
    debug => FIXME,
  );
  
  POE::Session->create(
    object_states => [
      ## FIXME _default handler
      $self => {
      
        '_start'   => '_emitter_start',
        '_stop'    => '_emitter_stop',

        'shutdown' => '_emitter_shutdown',

        '_default' => '_emitter_default',

      },
      $self => [ qw/

        _dispatch_notify

        _emitter_sigdie

      / ],
      ( 
        $self->has_object_states ? @{ $self->object_states } : ()
      ),
    ], 
  );

  1
}


## From our super:
around '_pluggable_event' => sub {
  my ($orig, $self) = splice @_, 0, 2;

  ## Receives Emitter_ev_* events (plugin_error, plugin_add etc)

  $self->emit( @_ );
};


### Methods.

sub _trigger_object_states {
  my ($self, $states) = @_;
  
  confess "object_states() should be an ARRAY or HASH"
    unless ref $states eq 'HASH' or ref $states eq 'ARRAY' ;

  my $die_no_startstop =
   "Should not have _start or _stop handlers defined; "
   ."use _emitter_started & _emitter_stopped" ;

  for (my $i=1; $i <= (scalar(@$states) - 1 ); $i+=2 ) {
    my $events = $states->[$i];
    if      (ref $events eq 'HASH') {
      confess $die_no_startstop 
        if defined $events->{'_start'}
        or defined $events->{'_stop'}
    } elsif (ref $events eq 'ARRAY') {
      confess $die_no_startstop
        if grep { $_ eq '_start' || $_ eq '_stop' } @$events;
    }
  }

  $states
}

sub _register_sender_session {
  ## Register a Session for notifications.
  my ($self, $target_id, @events) = @_;
  
  for my $event (@events) {
    ## FIXME
  }  
}

## FIXME delay() ?

## yield/call provide post()/call() frontends.
sub yield {
  my ($self, @args) = @_;
  $poe_kernel->post( $self->session_id, @args )
}

sub call {
  my ($self, @args) = @_;
  $poe_kernel->call( $self->session_id, @args )
}

## process/emit/emit_now bridge the plugin pipeline.
sub process {
  my ($self, $event, @args) = @_;
  ## Dispatch PROCESS events.
  ## process() events should _pluggable_process immediately
  ##  and return the EAT value.

  ## Dispatched to P_$event :
  $self->_pluggable_process( 'PROCESS', $event, \@args );

  ## FIXME should we notify sessions ... ?
}

sub emit {
  ## Async NOTIFY event dispatch.
  my ($self, $event, @args) = @_;
  $self->yield( '_dispatch_notify', $event, @args );
  1
}

sub emit_now {
  ## Synchronous NOTIFY event dispatch.
  my ($self, $event, @args) = @_;
  $self->call( '_dispatch_notify', $event, @args );
}

## Our Session's handlers:

sub _dispatch_notify {
  ## Dispatch a NOTIFY event
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  
  my ($event, @args) = @_[ARG0 .. $#_];

  my $prefix = $self->event_prefix;

  $event =~ s/^\Q$prefix//;

  ## Synchronously dispatched to our session as ->event_prefix . $event
  ##  These are considered notifications.
  ##  Session does NOT receive args as refs.
  $self->call( $prefix . $event, @args);

  ## Dispatched to N_$event after Sessions have been notified:
  $self->_pluggable_process( 'NOTIFY', $event, \@args );  
  
  ## FIXME notify registered sessions
}

sub _emitter_start {
  ## _start handler
  my ($kernel, $self)    = @_[KERNEL, OBJECT];
  my ($session, $sender) = @_[SESSION, SENDER];

  $self->set_session_id( $session->ID );

  $kernel->sig('DIE', '_emitter_sigdie' );

  $kernel->alias_set( $self->alias );

  if ($sender =! $kernel) {
    ## Have a parent session.

    ## refcount for this session.
    $kernel->refcount_increment( $sender->ID, 'Emitter running' );
    $self->_reg_sessions->{ $sender->ID }->{id} = $sender->ID;
    $self->_reg_sessions->{ $sender->ID }->{refc}++;

    ## register parent session for all notification events.
    $self->_reg_events->{ 'all' }->{ $sender->ID } = 1;

    ## Detach child session.
    $kernel->detach_myself;      
  }

  $self->call( 'emitter_started' );
}

sub _emitter_default {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($event, $args) = @_[ARG0, ARG1];

  ## Session received an unknown event.
  ## Dispatch it to any appropriate P_$event handlers.

  unless 
    ($event =~ /^_/ || $event =~ /^emitter_(?:started|stopped)$/) {

    $self->process( $event, @$args );
  }
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

sub _emitter_stop {
  ## _stop handler
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $self->call( 'emitter_stopped' );
}

sub _emitter_shutdown {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $kernel->alarm_remove_all;

  $self->_pluggable_destroy;

  $self->_emitter_drop_sessions;

  ## FIXME send shutdown event before dropping sessions ?
  ##  Syndicator sets a flag and calls a send_event ...
  ##  We could probably just set a bool and call _emitter_drop_sessions
  ##  from _dispatch_notify
}


## Handlers for listener sessions.
sub _emitter_register {
  my ($kernel, $self, $sender) = @_[KERNEL, OBJECT, SENDER];
  my @events = @_[ARG0 .. $#_];
  
  @events = 'all' unless @events;

  my $s_id = $sender->ID;

  $self->_reg_sessions->{$s_id}->{id} = $s_id;
  for my $event (@events) {
    $self->_reg_events->{$event}->{$s_id} = 1;
    
    $kernel->refcount_increment( $s_id, 'Emitter running' )
      if not $self->_reg_sessions->{$s_id}->{refc}
      and $s_id ne $self->session_id ;
  
    $self->_reg_sessions->{$s_id}->{refc}++
  }

  $kernel->post( $s_id, $self->event_prefix . "registered", $self )
}

sub _emitter_unregister {
  my ($kernel, $self, $sender) = @_[KERNEL, OBJECT, SENDER];
  my @events = @_[ARG0 .. $#_];

  @events = 'all' unless @events;

  my $s_id = $sender->ID;

  EV: for my $event (@events) {
    unless (delete $self->_reg_events->{$event}->{$s_id}) {
      ## Possible we should just not give a damn?
      warn "Cannot unregister $event for $s_id -- not registered";
      next EV
    }

    delete $self->_reg_events->{$event}
      ## No sessions left for this event.
      unless keys %{ $self->_reg_events->{$event} };

    --$self->_reg_sessions->{$s_id}->{refc};

    if ($self->_reg_sessions->{$s_id} < 1) {
      ## No events left for this session.
      delete $self->_reg_sessions->{$s_id};
      
      $kernel->refcount_decrement( $s_id, 'Emitter running' )
        unless $_[SESSION] == $sender;
    }

  } ## EV
}

sub _emitter_drop_sessions {
  my ($self) = @_;
  
  for my $id (keys %{ $self->_reg_sessions }) {
    my $count = $self->_reg_sessions->{$id};

    $poe_kernel->refcount_decrement(
      $id, 'Emitter running'
    ) until !$count;
    
    delete $self->_reg_sessions->{$id}
  }

  1
}




q[
 <tberman> who wnats to sing a song with me?
 <tberman> its the i hate php song
 * rac adds a stanza to tberman's song about braindead variable scoping
   that just made forums search return a bunch of false positives when 
   you search for posts by poster and return by topics  
];


=pod


=cut

