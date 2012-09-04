#!/usr/bin/env perl
use Module::Build;
use strict; use warnings;

my $class = Module::Build->subclass(
  class => 'IRC::Server::Pluggable::Builder',
  code => q{

    sub ACTION_versionify {
      my $self = shift;

      my $base = $self->base_dir;
      my $vers = $self->dist_version;

      ++$|;

      print "Versionifying ";
      require File::Find;
      File::Find->import('find');

      my $x;
      find(sub {
          if ($_ =~ /\.pm(.in)?$/) {
            my $path = $File::Find::name;
            open my $fh, '<', $path
              or die "open: $path $!";
            my @thisf = readline($fh);
            close $fh;

            my $package_l = $thisf[0] || return;
            my $pkg;
            unless (($pkg) = $package_l =~ /^package\s+(\S+)$/) {
              warn "\nSkipping, no package: $path\n";
              return
            }

            ++$x;
            print ". ";

            my $v_line = "our \$VERSION = '$vers';\n";

            if ($thisf[1] =~ /VERSION/) {
              $thisf[1] = $v_line
            }

            open $fh, '>', $path
              or die "open: $path $!";
            print $fh @thisf;
            close $fh;
          }
        },
        $base."/lib"
      );
      print "\n$x modules\n";
    }

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
    'perl'     => '5.12.1',

    'Carp'         => 0,
    'Carp::Always' => 0,

    'Exporter' => 0,
    'Socket'   => 2,

    'strictures'             => 1,
    'namespace::clean'       => '0.23',

    'IRC::Server::Tree'      => '0.03',
    'IRC::Utils'             => 0,

    'Moo'                    => '1.000003',
    'MooX::Types::MooseLike' => 0,

    'Net::IP::Minimal'       => 0,

    'Object::Pluggable'      => 0,

    'POE'                    => '1.3',
    'POE::Component::Client::DNS'          => 0,
    'POE::Component::Client::Ident::Agent' => 0,
    'POE::Component::SSLify' => '1.006',
    'POE::Filter::IRCD'      => 0,
    'POE::Filter::Zlib'      => 0,

    'Try::Tiny'              => 0,
  },
);

$build->create_build_script;

__END__
Cake.
