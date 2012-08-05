package IRC::Server::Pluggable::Dispatcher;

## FIXME
##  - bridge backend and protocol sessions
##    - parse Event objs and dispatch to Protocol

## 

use 5.12.1;
use strictures 1;

use Carp;
use Moo;
use POE;

use IRC::Server::Pluggable qw/
  Emitter
  Types
/;


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
        
        ## FIXME
      },
      
      $self => [
        'ircsock_connection_idle',
        'ircsock_input',
        ## FIXME
      ],
      
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

sub ircsock_connection_idle {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  
  $self->emit( 'connection_idle', @_[ARG0 .. $#_] );
}

sub ircsock_input {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $ev)     = @_[ARG0, ARG1];

  my $from_type = 
    $conn->is_peer   ? 'peer'   : 
    $conn->is_client ? 'client' : 
                       'unknown';

  my $cmd = lc($ev->{command});

  my $event_name;
  given ($from_type) {
    $event_name = 'peer_'.$ev->{command} when "peer"  ;
    $event_name = 'user_'.$ev->{command} when "client";
    ## FIXME need an 'unknown' dispatcher
  }

  ## process() via our plugin pipeline:
  return 
    if $self->process( $event_name, $conn, $ev ) == EAT_NONE;
  ## .. then emit() to registered sessions:
  $self->emit( $event_name, $conn, $ev );
}


## FIXME method to relay output?


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
