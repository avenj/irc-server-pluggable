package IRC::Server::Pluggable::IRC::Config;
use Defaults::Modern;

use IRC::Server::Pluggable qw/
  Types
/;

use Moo;
use MooX::late;
use namespace::clean;


## FIXME
##  - Config::Auth for users/opers/peers?

has admin_info => (
  lazy      => 1,
  is        => 'ro',
  isa       => ArrayObj,
  coerce    => 1,
  predicate => 'has_admin_info',
  writer    => 'set_admin_info',
  default   => sub { array },
);

has max_chan_length => (
  lazy      => 1,
  is        => 'ro',
  isa       => Int,
  predicate => 'has_max_chan_length',
  writer    => 'set_max_chan_length',
  default   => sub { 30 },
);

has max_nick_length => (
  lazy      => 1,
  is        => 'ro',
  isa       => Int,
  predicate => 'has_max_nick_length',
  writer    => 'set_max_nick_length',
  default   => sub { 9 },
);

has max_msg_targets => (
  lazy      => 1,
  is        => 'ro',
  isa       => Int,
  predicate => 'has_max_msg_targets',
  writer    => 'set_max_msg_targets',
  default   => sub { 4 },
);

has motd => (
  lazy      => 1,
  is        => 'ro',
  isa       => ArrayObj,
  coerce    => 1,
  predicate => 'has_motd',
  writer    => 'set_motd',
  default   => sub { array },
);

has network_name => (
  lazy      => 1,
  is        => 'ro',
  isa       => Str,
  predicate => 'has_network_name',
  writer    => 'set_network_name',
  default   => sub { 'NoNetworkDefined' },
);

has server_name => (
  required  => 1,
  is        => 'ro',
  isa       => Str,
  predicate => 'has_server_name',
  writer    => 'set_server_name',
);


1;
