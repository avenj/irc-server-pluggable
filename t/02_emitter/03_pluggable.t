use Test::More tests => 3;
use strict; use warnings FATAL => 'all';

use POE;

{
  package MyEmitter;
  
  use strict; use warnings FATAL => 'all';
  
  use POE; 
  use Test::More;
  
  use IRC::Server::Pluggable::Constants;

  use Moo;
  extends 'IRC::Server::Pluggable::Emitter'; 
  
  sub BUILD {
    my ($self) = @_;
    
    $self->set_alias( 'SimpleEmitter' );
    
    $self->set_object_states(
      [
        $self => [
          'emitter_started',
          'emitter_stopped',
          'shutdown',
        ],
      ],
    );
    
    $self->_start_emitter;
  }

  sub emitter_started {
    pass("Emitter started");
  }
  
  sub emitter_stopped {
    pass("Emitter stopped");
  }

  sub shutdown {
    my ($kernel, $self) = @_[KERNEL, OBJECT];
    
    pass("shutdown called");
    
    $self->call( 'shutdown_emitter' );
  }
  
}

POE::Session->create(
  package_states => [
    main => [ qw/
 
      _start
      
      emitted_registered

    / ],
  ],
);

$poe_kernel->run;

sub _start {
  my $emitter = MyEmitter->new;
  my $sess_id = $emitter->session_id;
  $poe_kernel->post( $sess_id, 'register' );
}

sub emitted_registered {

}
