package IRC::Server::Pluggable::IRC::Peer;
## Base class for Peers.
## Overridable by Protocols.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable::Types;


use namespace::clean -except => 'meta';


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
    my $wantclass = "IRC::Server::Pluggable::Backend::Connect";
    is_Object($_[0])
      and $_[0]->isa($wantclass)
      or confess "$_[0] is not a $wantclass"
  },
);

has 'name' => (
  required => 1,
  is       => 'ro',
  isa      => Str,
  writer   => 'set_name',
);

has 'linked'  => (
  ## Servers introduced by this Peer, if applicable.
  lazy      => 1,
  is        => 'ro',
  writer    => 'set_peers',
  predicate => 'has_peers',
  clearer   => 'clear_peers',
  isa       => HashRef,
  default   => sub { {} },
);

## FIXME should we track a list of user identifiers introduced by
##  a peer here?

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
      carp "No route() and no conn() available, using empty route";
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

## FIXME methods  to add/del ->linked() peers

1;
