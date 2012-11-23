use Test::More;
use strict; use warnings FATAL => 'all';

use lib 't/inc';
use ISPTestUtils;

use POE qw/
  Component::Client::TCP
/;

BEGIN {
  use_ok( 'IRC::Server::Pluggable::Backend' );
}

my $backend = IRC::Server::Pluggable::Backend->spawn(
  ## FIXME
  ##  test with ssl_opts
);
isa_ok( $backend, 'IRC::Server::Pluggable::Backend' );


POE::Session->create(
  package_states => [
    main => [ qw/

      _start
      _shutdown

      ircsock_registered

      ircsock_listener_created

    / ],
  ],
  heap => { backend => $backend },
);

$poe_kernel->run;

my $controller_expected = {
  'Got ircsock_registered' => 1,
  'Got ircsock_listener_created' => 1,
};
my $controller_got;

sub _start {
  my ($k, $heap) = @_[KERNEL, HEAP];

  $k->post( $heap->{backend}->session_id, 'register' );

  $heap->{backend}->create_listener(
    protocol => 4,
    bindaddr => '127.0.0.1',
    port     => 0,
  );
}

sub _shutdown {
  my ($k, $heap) = @_[KERNEL, HEAP];

  $k->delay('_shutdown');
  $k->post( $heap->{backend}->session_id, 'shutdown' );
}

sub ircsock_registered {
  my ($k, $heap) = @_[KERNEL, HEAP];
  my $backend = $_[ARG0];

  $controller_got->{'Got ircsock_registered'}++;

  isa_ok( $backend, 'IRC::Server::Pluggable::Backend' );
}

sub ircsock_listener_created {
  my ($k, $heap) = @_[KERNEL, HEAP];
  my $listener = $_[ARG0];

  $controller_got->{'Got ircsock_listener_created'}++;

  isa_ok( $listener, 'IRC::Server::Pluggable::Backend::Listener' );

  my $addr = $listener->addr;
  ok( $addr, 'addr() from listener_created' );
  my $port = $listener->port;
  ok( $port, 'port() from listener_created' );

  ## FIXME test a connect to our listener's port..?

  $k->yield('_shutdown');
}

test_expected_ok($controller_got, $controller_expected,
  'Expected results from controller'
);

done_testing();
