package IRC::Server::Pluggable::Emitter;
our $VERSION = 1;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable::Types;

use POE;

use Object::Pluggable::Constants qw/:ALL/;

extends 'Object::Pluggable';


has 'alias' => (
  lazy => 1,
  is   => 'ro',
  isa  => Str,
  predicate => 'has_alias',
  writer    => 'set_alias',
  default   => sub { "$_[0]" },
);

has 'debug' => (
  lazy => 1,
  is   => 'ro',
  isa  => Bool,
  predicate => 'has_debug',
  writer    => 'set_debug',
  default   => sub { 0 },
);

has 'event_prefix' => (
  lazy => 1,
  is   => 'ro',
  isa  => Str,
  predicate => 'has_event_prefix',
  writer    => 'set_event_prefix',
  default   => sub { "Emitter_ev_" },
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
  default   => sub { "Emitter_" },
);

has 'session_id' => (
  lazy => 1,
  is   => 'ro',
  isa  => Defined,  
  predicate => 'has_session_id',
  writer    => 'set_session_id',
);


has '_emitter_reg_sessions' => (
  ## ->{ $session_id } = { refc => $ref_count, id => $id };
  lazy => 1,
  is   => 'ro',
  isa  => HashRef,
  default => sub { {} },
);

has '_emitter_reg_events' => (
  ## ->{ $event }->{ $session_id } = 1
  lazy => 1,
  is   => 'ro',
  isa  => HashRef,
  default => sub { {} },
);


sub import {
  my $self = shift;
  
  my $pkg = caller();
  
  {
    no strict 'refs';
    for (qw/ EAT_NONE EAT_CLIENT EAT_PLUGIN EAT_ALL /) {
      my $realval = ( 'Object::Pluggable::Constants::PLUGIN_'.$_ )->();
      *{ $pkg .'::' .$_ } = sub () { $realval };
    }
  }    
}


sub _start_emitter {
  ## Call to spawn Session.
  ##   my $self = $class->new(
  ##     alias           => Emitter session alias
  ##     debug           => Debug true/false
  ##     event_prefix    => Session event prefix (Emitter_ev_)
  ##     register_prefix => _register/_unregister prefix (Emitter_)
  ##     object_states   => Extra object_states for Session
  ##   )->_start_emitter();
  my ($self) = @_;

  $self->_pluggable_init(
    prefix     => $self->event_prefix,
    reg_prefix => $self->register_prefix,

    types => {

      ## PROCESS type events are handled synchronously.
      ## Handlers begin with P_*
      'PROCESS' => 'P',

      ## NOTIFY type events are dispatched asynchronously.
      ## Handlers begin with N_*
      'NOTIFY'  => 'N',
    },

    debug => $self->debug,
  );
  
  POE::Session->create(
    object_states => [

      $self => {
      
        '_start'   => '_emitter_start',
        '_stop'    => '_emitter_stop',
        
        'register'   => '_emitter_register',
        'unregister' => '_emitter_unregister',

        '_default' => '_emitter_default',

      },

      $self => [ qw/
        _emitter_shutdown

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

  ## Receives plugin_error, plugin_add etc

  $self->emit( @_ );
};


### Methods.

sub _trigger_object_states {
  my ($self, $states) = @_;
  
  confess "object_states() should be an ARRAY or HASH"
    unless ref $states eq 'HASH' or ref $states eq 'ARRAY' ;

  my $die_no_startstop =
   "Should not have _start or _stop handlers defined; "
   ."use emitter_started & emitter_stopped" ;

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

## TODO alarm/delay frontends, perhaps?

## yield/call provide post()/call() frontends.
sub yield {
  my ($self, @args) = @_;
  $poe_kernel->post( $self->session_id, @args )
}

sub call {
  my ($self, @args) = @_;
  $poe_kernel->call( $self->session_id, @args )
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

sub process {
  my ($self, $event, @args) = @_;
  ## Dispatch PROCESS events.
  ## process() events should _pluggable_process immediately
  ##  and return the EAT value.

  ## Dispatched to P_$event :
  $self->_pluggable_process( 'PROCESS', $event, \@args );

  ## FIXME should we notify sessions at all ... ? Worth a ponder.
}


sub __incr_ses_refc {
  my ($self, $sess_id) = @_;
  ++$self->_emitter_reg_sessions->{$sess_id}->{refc}
}

sub __decr_ses_refc {
  my ($self, $sess_id) = @_;
  --$self->_emitter_reg_sessions->{$sess_id}->{refc};
  $self->_emitter_reg_sessions->{$sess_id}->{refc} = 0
    unless $self->_emitter_reg_sessions->{$sess_id}->{refc} > 0      
}

sub __get_ses_refc {
  my ($self, $sess_id) = @_;
  $self->_emitter_reg_sessions->{$sess_id}->{refc}
    if exists $self->_emitter_reg_sessions->{$sess_id}
}

sub __reg_ses_id {
  my ($self, $sess_id) = @_;
  $self->_emitter_reg_sessions->{$sess_id}->{id} = $sess_id
}


## Our Session's handlers:

sub _dispatch_notify {
  ## Dispatch a NOTIFY event
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($event, @args) = @_[ARG0 .. $#_];

  my $prefix = $self->event_prefix;

  ## May have event_prefix (such as $prefix.'plugin_error')
  $event =~ s/^\Q$prefix//;

  my %sessions;

  for my $regev ('all', $event) {
    if (exists $self->_emitter_reg_events->{$regev}) {
      next unless keys %{ $self->_emitter_reg_events->{$regev} };
      
      $sessions{$_} = 1 
        for values %{ $self->_emitter_reg_events->{$regev} };
    }
  }

  ## Our own session will get ->event_prefix . $event first
  $kernel->call( $_[SESSION], $prefix.$event, @args )
    if delete $sessions{ $_[SESSION]->ID };

  ## Dispatched to N_$event after Sessions have been notified:
  my $eat = $self->_pluggable_process( 'NOTIFY', $event, \@args );
  
  unless ($eat == PLUGIN_EAT_ALL) {
    ## Notify registered sessions.
    $kernel->call( $_, $prefix.$event, @args )
      for keys %sessions;
  }

  ## Received emitted 'shutdown', drop sessions.
  $self->_emitter_drop_sessions
    if $event eq 'shutdown';
}

sub _emitter_start {
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
    $self->_emitter_reg_events->{ 'all' }->{ $s_id } = 1;

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

sub _emitter_stop {
  ## _stop handler
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $self->call( 'emitter_stopped' );
}

sub _emitter_shutdown {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## Send this session an _emitter_shutdown to clean up.

  $kernel->alarm_remove_all;

  $self->_pluggable_destroy;

  $self->_emitter_drop_sessions;
}


## Handlers for listener sessions.
sub _emitter_register {
  my ($kernel, $self, $sender) = @_[KERNEL, OBJECT, SENDER];
  my @events = @_[ARG0 .. $#_];
  
  @events = 'all' unless @events;

  my $s_id = $sender->ID;

  ## Add to our known sessions.
  $self->__reg_ses_id( $s_id );

  for my $event (@events) {
    ## Add session to registered event lists.
    $self->_emitter_reg_events->{$event}->{$s_id} = 1;
    
    ## Make sure registered session hangs around
    ##  (until _unregister or shutdown)
    $kernel->refcount_increment( $s_id, 'Emitter running' )
      if not $self->__get_ses_refc($s_id)
      and $s_id ne $self->session_id ;
  
    $self->__incr_ses_refc( $s_id );
  }

  $kernel->post( $s_id, $self->event_prefix . "registered", $self )
}

sub _emitter_unregister {
  my ($kernel, $self, $sender) = @_[KERNEL, OBJECT, SENDER];
  my @events = @_[ARG0 .. $#_];

  @events = 'all' unless @events;

  my $s_id = $sender->ID;

  EV: for my $event (@events) {
    unless (delete $self->_emitter_reg_events->{$event}->{$s_id}) {
      ## Possible we should just not give a damn?
      warn "Cannot unregister $event for $s_id -- not registered";
      next EV
    }

    delete $self->_emitter_reg_events->{$event}
      ## No sessions left for this event.
      unless keys %{ $self->_emitter_reg_events->{$event} };

    $self->__decr_ses_refc($s_id);

    unless ($self->__get_ses_refc($s_id)) {
      ## No events left for this session.
      delete $self->_emitter_reg_sessions->{$s_id};
      
      $kernel->refcount_decrement( $s_id, 'Emitter running' )
        unless $_[SESSION] == $sender;
    }

  } ## EV
}

sub _emitter_drop_sessions {
  my ($self) = @_;
  
  for my $id (keys %{ $self->_emitter_reg_sessions }) {
    my $count = $self->__get_ses_refc($id);

    $poe_kernel->refcount_decrement(
      $id, 'Emitter running'
    ) while $count-- > 0;
    
    delete $self->_emitter_reg_sessions->{$id}
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

=head1 NAME

IRC::Server::Pluggable::Emitter - Event emitter base class

=head1 SYNOPSIS

  package My::EventEmitter;
  
  use Moo;
  extends 'IRC::Server::Pluggable::Emitter';

  FIXME

=head1 DESCRIPTION

This is a base class for a POE-oriented observer pattern implementation 
based on L<POE::Component::Syndicator>.

This class inherits from L<Object::Pluggable>; the documentation 
for plugin manipulation methods can be found there.

  FIXME

=head2 Creating an Emitter



=head2 Registering plugins

=head2 Registering sessions

=head2 Receiving events

=head3 NOTIFY events

=head3 PROCESS events

=head2 Sending events

=head3 emit

=head3 emit_now

=head3 process

FIXME


=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

Based largely on L<POE::Component::Syndicator>-0.06 -- I needed something 
Moo-ish I could tweak.

=cut

