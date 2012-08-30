package IRC::Server::Pluggable::IRC::Config;

use Carp;
use Moo;

use 5.12.1;
use strictures 1;

## FIXME
##  - Config::Auth for users/opers/peers?

has 'max_chan_length' => (
  lazy      => 1,
  isa       => Int,
  is        => 'ro',
  predicate => 'has_max_chan_length',
  writer    => 'set_max_chan_length',
  default   => sub { 30 },
);

has 'max_nick_length' => (
  lazy      => 1,
  isa       => Int,
  is        => 'ro',
  predicate => 'has_max_nick_length',
  writer    => 'set_max_nick_length',
  default   => sub { 9 },
);

has 'max_msg_targets' => (
  lazy      => 1,
  isa       => Int,
  is        => 'ro',
  predicate => 'has_max_msg_targets',
  writer    => 'set_max_msg_targets',
  default   => sub { 4 },
);

has 'network_name' => (
  lazy      => 1,
  is        => 'ro',
  isa       => Str,
  predicate => 'has_network_name',
  writer    => 'set_network_name',
  default   => sub { 'NoNetworkDefined' },
);

has 'server_name' => (
  required  => 1,
  is        => 'ro',
  isa       => Str,
  predicate => 'has_server_name',
  writer    => 'set_server_name',
);


1;
