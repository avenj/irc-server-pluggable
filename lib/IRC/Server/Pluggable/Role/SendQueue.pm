package IRC::Server::Pluggable::Role::SendQueue;
use Defaults::Modern;

use Moo::Role;

has sendq_buf => (
  lazy    => 1,
  is      => 'ro',
  isa     => TypedArray[Object],
  default => sub { array_of Object },
);

1;
