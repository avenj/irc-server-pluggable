package IRC::Server::Pluggable::IRC::Config;

use Carp;
use Moo;

use 5.12.1;
use strictures 1;

has 'max_chan_length' => (
  lazy => 1,

  isa => Int,
  is  => 'rw',

  default => sub { 30 },
);

has 'max_nick_length' => (
  lazy => 1,

  isa => Int,
  is  => 'rw',

  default => sub { 9 },
);

has 'max_msg_targets' => (
  lazy => 1,

  isa => Int,
  is  => 'rw',

  default => sub { 4 },
);

has 'network_name' => (
  lazy => 1,

  is  => 'rw',
  isa => Str,

  default => sub { 'NoNetworkDefined' },
);

has 'server_name' => (
  required => 1,

  is  => 'rw',
  isa => Str,
);



1;
