use Test::More tests => 4;
use strict; use warnings FATAL => 'all';

use POE;

BEGIN {
  use_ok( 'IRC::Server::Pluggable::Backend' );
}

my $backend = IRC::Server::Pluggable::Backend->spawn(
  ## FIXME
  ##  test with ssl_opts
);
isa_ok( $backend, 'IRC::Server::Pluggable::Backend' );

## FIXME
## test with listeners?

POE::Session->create(
  package_states => [
    main => [ qw/

      _start
      _shutdown
      
      ircsock_registered

    / ],
  ],
  heap => { backend => $backend },
);

$poe_kernel->run;
exit 0;

sub _start {
  my ($k, $heap) = @_[KERNEL, HEAP];
  
  $k->post( $heap->{backend}->session_id, 'register' );
}

sub _shutdown {
  my ($k, $heap) = @_[KERNEL, HEAP];
  
  $k->delay('_shutdown');
  $k->post( $heap->{backend}->session_id, 'shutdown' );
}

sub ircsock_registered {
  my ($k, $heap) = @_[KERNEL, HEAP];
  my $backend = $_[ARG0];
  
  pass("Received ircsock_registered");
  
  isa_ok( $backend, 'IRC::Server::Pluggable::Backend' );
  
  $k->yield('_shutdown'); ## DONE TESTING
}

## FIXME
