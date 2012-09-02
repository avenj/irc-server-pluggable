#!/usr/bin/env perl;

use 5.12.1;
use IRC::Server::Pluggable::IRC::Tree;
use strictures 1;
use Data::Dumper;

my $t = IRC::Server::Pluggable::IRC::Tree->new;

$t->add_node_to_top('hubA');
$t->add_node_to_name('hubA', 'leafA');
$t->add_node_to_name('hubA', 'leafB');
$t->add_node_to_name('hubA', 'hubB');

$t->add_node_to_name('hubB', 'leafC');
$t->add_node_to_name('hubB', 'leafD');


$t->add_node_to_top('hubZ');
$t->add_node_to_name('hubZ', 'leafZ');
$t->add_node_to_name('hubZ', 'leafY');
$t->add_node_to_name('hubZ', 'hubX');

$t->add_node_to_name('hubX', 'hubY');
$t->add_node_to_name('hubX', 'leafX');
$t->add_node_to_name('hubX', 'leafW');

$t->add_node_to_name('hubY', 'hubW');
$t->add_node_to_name('hubY', 'leafV');

$t->add_node_to_name('hubW', 'leafU');

$t->print_map;

while (1) {
  print "Give me a name, get a path: ";
  my $path_to = <STDIN>;
  chomp($path_to);

  unless ($path_to) {
    $t->print_map and next
  }

  my $route = $t->path_to_server($path_to);
  my $hops  = $t->path_to_server_indexes($path_to);
  if ($route) {
    print Dumper $route;
    print " -> (".join(', ', @$hops).")\n";
  } else {
    say "No route found"
  }
}
