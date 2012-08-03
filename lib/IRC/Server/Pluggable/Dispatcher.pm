package IRC::Server::Pluggable::Dispatcher;

## FIXME
## Dispatcher should:
##  - take a Backend and a Protocol session?
##    - maybe accept these via events instead?
##    - or take spawn opts here and create them accordingly?
##  - register with Backend
##  - bridge backend and protocol sessions
##    - parse Event objs and dispatch to Protocol cmd handlers

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable::Types;

use POE;

has 'backend' => (
  required => 1,

  isa => BackendClass,
  is  => 'rwp',
);

has 'protocol_session' => (
  is => 'rwp',
  
  ## FIXME
);

has 'session_id' => (
  is => 'ro',
  writer => 'set_session_id',  
);

sub spawn {
  my $class = shift;

  my %args = @_;
  $args{lc $_} = delete $args{$_} for keys $args;

  ## FIXME spawn a Backend and Protocol unless one's been provided
  ## 
  my $self = ref($class) ? $class : $class->new(
    %$args
  );

  my $sess_id = POE::Session->create(
    object_states => [
      $self => {
        '_start' => '_start',
        '_stop'  => '_stop',
        
        'shutdown' => '_shutdown',
      },
    ],
  )->ID;

  $self->set_session_id( $sess_id );

  $self
}

sub _start {

}

sub _stop {

}

sub shutdown {
  my $self = shift;
  
  $poe_kernel->post( $self->session_id,
    'shutdown',
    @_
  );
  
  1
}

sub _shutdown {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $kernel->post( $self->backend->session_id,
    'shutdown',
    @_[ARG0 .. $#_]
  );
}


1;
