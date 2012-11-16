package IRC::Server::Pluggable::IRC::Config;

use Carp;
use Moo;

use 5.12.1;
use strictures 1;

use IRC::Server::Pluggable::Types;


use namespace::clean -except => 'meta';


## FIXME
##  - Config::Auth for users/opers/peers?

has 'admin_info' => (
  lazy      => 1,
  isa       => ArrayRef,
  is        => 'ro',
  predicate => 'has_admin_info',
  writer    => 'set_admin_info',
  default   => sub { [ ] },
);

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

has 'motd' => (
  lazy      => 1,
  isa       => ArrayRef,
  is        => 'ro',
  predicate => 'has_motd',
  writer    => 'set_motd',
  default   => sub { [ ] },
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
