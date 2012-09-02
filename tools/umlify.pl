#!/usr/bin/env perl
use strictures 1;

my ($root, $out);
use Getopt::Long;
GetOptions(
  'root=s' => \$root,
  'out=s'  => \$out,
);

die "Usage:  --root=DIR --out=FILE\n"
  unless defined $root and defined $out;

use File::Find;
use UML::Class::Simple;

die "No root $root"
  unless -d $root;

my @files;
find(sub {
    push(@files, $File::Find::name)
      if $_ =~ /\.pm$/;
  },
  $root
);

my @classes = classes_from_files( \@files );
my $uml = UML::Class::Simple->new( \@classes );
$uml->as_png( $out );
