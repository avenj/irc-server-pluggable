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

say "Enter method names and params, blank line prints map";

my $run = 1;
while ($run) {
  print "cmd> ";

  my $input = <STDIN>;
  chomp($input);
  unless ($input) {
    $t->print_map;
    next
  }

  my ($cmd, @params) = split ' ', $input;
  $cmd = lc($cmd//'');

  if ($cmd eq 'exit' || $cmd eq 'quit') {
    $run = 0;
    next
  }

  unless ( $t->can($cmd) ) {
    $t->print_map;
    next
  }

  print(
    Dumper($t->$cmd(@params))
  );
}
