package IRC::Server::Pluggable::Emitter;
our $VERSION;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use Object::Pluggable::Constants qw/:ALL/;

extends 'Object::Pluggable';

use IRC::Server::Pluggable qw/
  Types
/;

has 'alias' => (
  ## Optionally instantiate with a kernel alias:
  lazy => 1,
  is   => 'ro',
  isa  => Str,
  predicate => 'has_alias',
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
      'PROCESS => 'P',
      'NOTIFY' => 'N',
    },
    debug =>
  );
  
  POE::Session->create(
    object_states => [
      $self => {
      
        '_start'   => '_emitter_start',
        '_stop'    => '_emitter_stop',

        'shutdown' => '_emitter_shutdown',

      },
      $self => [ qw/

        _dispatch_event

      / ],
    ], 
  );
  
  
}


## From our super:
around '_pluggable_event' => sub {
  my ($orig, $self) = splice @_, 0, 2;

  ## Receives Emitter_ev_* events (_pugin_error, plugin_add etc)

  $self->emit( @_ );
};


## Our methods:
sub process {
  my ($self, $event, @args) = @_;
  ## Dispatch PROCESS events
  ## process() events should _pluggable_process immediately
  ##  and return the EAT value.
  $self->_pluggable_process( 'PROCESS', $event, \@args );
}

sub emit {
  my ($self, $event, @args) = @_;
  ## Notification events
  $self->yield( '_dispatch_event', $event, @args );
  1
}

sub emit_now {
  my ($self, $event, @args) = @_;
  ## Synchronous notification events
  $self->call( '_dispatch_event', $event, @args );
}

sub yield {
  my ($self, @args) = @_;
  $poe_kernel->post( $self->session_id, @args )
}

sub call {
  my ($self, @args) = @_;
  $poe_kernel->call( $self->session_id, @args )
}

## Our Session's handlers:

sub _dispatch_event {
  ## Dispatch a NOTIFY event
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  
  my ($event, @args) = @_[ARG0 .. $#_];

  my $prefix = $self->event_prefix;

  $event =~ s/^\Q$prefix//;
    
  $self->_pluggable_process( 'NOTIFY', $event, \@args );  
}

sub _emitter_start {
  ## _start handler
  my ($kernel, $self, $session) = @_[KERNEL, OBJECT, SESSION];
  
  $self->set_session_id( $session->ID );

  if ( $self->has_alias ) {
    ## Set alias
  } else {
    ## Incr refcount
  }
}

sub _emitter_stop {
  ## _stop handler
}

sub _emitter_shutdown {
  ## FIXME call _pluggable_destroy
  
}


q{
 <tberman> who wnats to sing a song with me?
 <tberman> its the i hate php song
 * rac adds a stanza to tberman's song about braindead variable scoping
   that just made forums search return a bunch of false positives when 
   you search for posts by poster and return by topics  
};


=pod


=cut

