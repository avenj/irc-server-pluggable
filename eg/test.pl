#!/usr/bin/env perl

use 5.12.1;
use strictures 1;

use POE;

use IRC::Server::Pluggable::Backend;

use Data::Dumper;

POE::Session->create(
  package_states => [
    main => [ qw/
      
      _start
      
      _default
    
    / ],
  ],
);

POE::Kernel->run;

sub _start {
  my $backend = IRC::Server::Pluggable::Backend->spawn(
  
  );
  
  POE::Kernel->post( $backend->session_id, 'register' );

  POE::Kernel->post( $backend->session_id,
    'create_listener',
    bindaddr => '127.0.0.1',
    port     => 9500,
  );
}

sub _default {
  my ($event, $args) = @_[ARG0, ARG1];
  say "$event - ".Dumper($args)
}
