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
use POE;

use IRC::Server::Pluggable::Types;


extends 'IRC::Server::Pluggable::Emitter';


has 'backend' => (
  required => 1,

  isa => BackendClass,
  is  => 'rwp',
);


sub BUILD {
  my ($self) = @_;

  $self->set_event_prefix( "backend_ev_" )
    unless $self->has_event_prefix;

  $self->set_object_states(
    [
      $self => {
      
        'shutdown' => '_shutdown',
        
        'ircsock_input' =>
             
        ## FIXME
      },
      
      ( $self->has_object_states ? @{$self->object_states} : () ),
    ],
  );

  
  $self->_start_emitter;
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
  
  $self->_yield( '_emitter_shutdown' );
}

## FIXME
##  $self->process() incoming IRC events
##  Protocol session can register with Dispatcher
##  Processed events can be emitted to registered Protocol session


q{
 <nitric> the more you think about facebook actions in real life, the 
  weirder facebook seems
 <nitric> irl, I DON'T want people writing on my wall at 1am    
 <nitric> or poking me   
 <Schroedingers_hat> HEY YOU HELP ME WITH MY GARDEN!    
 <Schroedingers_hat> Who are you?    
 <Schroedingers_hat> GIVE ME SOME CARROTS
};


=pod

=cut
