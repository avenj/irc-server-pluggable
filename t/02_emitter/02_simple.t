use Test::More tests => 8;
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
  
  sub P_things {
    pass("Emitter received P_things");
    is( $_[ARG0], 1, "P_things had expected args" );
  }
  
}

POE::Session->create(
  package_states => [
    main => [ qw/
 
      _start
      
      emitted_registered

      emitted_test_emit

    / ],
  ],
);

$poe_kernel->run;

sub _start {
  my $emitter = MyEmitter->new;
  my $sess_id;
  ok( $sess_id = $emitter->session_id, 'session_id()' );
  $poe_kernel->post( $sess_id, 'register' );
}

sub emitted_registered {
  ## Test 'registered' ev
  isa_ok( $_[ARG0], 'IRC::Server::Pluggable::Emitter' );
  ## Test process()
  $_[ARG0]->process( 'things', 1 );
  ## Test emit()
  $_[ARG0]->emit( 'test_emit', 1 );
}

sub emitted_test_emit {
  ## emit() received
  is( $_[ARG0], 1, 'emitted_test()' );
  $poe_kernel->post( $_[SENDER], 'shutdown' );  
}
