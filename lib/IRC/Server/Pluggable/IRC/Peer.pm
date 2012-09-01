package IRC::Server::Pluggable::IRC::Peer;
## Base class for Peers.
## Overridable by Protocols.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable qw/
  Types
/;

has 'conn' => (
  ## Our directly-linked peers should have a Backend::Connect
  lazy      => 1,
  ## Also tracked in Backend:
  weak_ref  => 1,
  is        => 'ro',
  predicate => 'has_conn',
  writer    => 'set_conn',
  clearer   => 'clear_conn',
  isa       => sub {
    is_Object($_[0])
      and $_[0]->isa('IRC::Server::Pluggable::Backend::Connect')
      or confess "$_[0] is not a IRC::Server::Pluggable::Backend::Connect"
  },
);

has 'name' => (
  required => 1,
  is       => 'ro',
  isa      => Str,
  writer   => 'set_name',
);

has 'peers'  => (
  ## A Peer can have its own Peers
  ## FIXME
  lazy      => 1,
  is        => 'ro',
  writer    =>
  predicate =>
  clearer   =>
  isa       =>
);

has 'route' => (
  ## Either our Connect's wheel_id or the wheel_id of the next hop peer.
  lazy      => 1,
  is        => 'ro',
  isa       => Str,
  writer    => 'set_route',
  predicate => 'has_route',
  clearer   => 'clear_route',
  default   => sub {
    my ($self) = @_;

    unless ($self->has_conn) {
      carp "No route() and no conn() available, using empty route"
      return ''
    }

    $self->conn->wheel_id,
  },
);

sub BUILD {
  my ($self) = @_;

  unless ($self->has_conn || $self->has_route) {
    confess
      "A Peer needs either a conn() or a route() at construction time"
  }
}

1;
