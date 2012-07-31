#!/usr/bin/env perl
use Module::Build;
use strict; use warnings;

my $class = Module::Build->subclass(
  class => 'IRC::Server::Pluggable::Builder',
  code => q{
  
  },
);

my $build = $class->new(
  module_name => 'IRC::Server::Pluggable',
  license     => 'perl',

  dist_abstract => 'POE IRC server components',
  dist_author   => 'Jon Portnoy <avenj@cobaltirc.org>',

  recursive_test_files => 1,
  
  create_readme      => 1,
  create_makefile_pl => 'small',

  configure_requires => {
    'Module::Build' => '0.40',
  },
  
  build_requires => {
    'Test::More'      => 0,
    'Test::Exception' => 0,
  },
  
  requires => {
    'perl' => '5.12.1',

    'Carp'     => 0,
    'Exporter' => 0,
    'Socket'   => 2,
    
    'strictures' => 1,
    
    'POE'        => '1.3',
    'POE::Component::SSLify' => '1.006',
#    'POE::Component::Syndicator' => '0.06',
    
    'Try::Tiny'  => 0,
  },
);

$build->create_build_script;

__END__
Cake.
