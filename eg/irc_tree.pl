#!/usr/bin/env perl;

use IRC::Server::Pluggable::IRC::Tree;
use strictures 1;


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


$t->print_map;
