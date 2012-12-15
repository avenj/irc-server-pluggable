package IRC::Server::Pluggable::IRC::Peer;
## Base class for Peers.
## Overridable by Protocols.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable 'Types';

use Exporter 'import';
our @EXPORT = 'irc_peer';

use namespace::clean -except => 'import';


sub irc_peer {
  __PACKAGE__->new(@_)
}

with 'IRC::Server::Pluggable::Role::Metadata';
with 'IRC::Server::Pluggable::Role::Routable';

sub BUILD {
  my ($self) = @_;

  unless ($self->has_conn || $self->has_route) {
    confess
      "A Peer needs either a conn() or a route() at construction time"
  }
}


has 'casemap' => (
  ## For use with ->lower / ->upper; ascii should do
  lazy    => 1,
  is      => 'ro',
  default => sub { 'ascii' },
);
with 'IRC::Server::Pluggable::Role::CaseMap';

has 'is_bursting' => (
  lazy    => 1,
  is      => rw,
  isa     => Bool,
  default => sub { 0 },
);

has 'linked'  => (
  ## Servers introduced by this Peer, if applicable.
  ## (weak-refs to Peer objs?)
  lazy      => 1,
  is        => 'ro',
  writer    => 'set_peers',
  predicate => 'has_peers',
  clearer   => 'clear_peers',
  isa       => HashRef,
  default   => sub { {} },
);

has 'name' => (
  required => 1,
  is       => 'ro',
  isa      => Str,
  writer   => 'set_name',
);


## FIXME methods  to add/del ->linked() peers ?

1;
