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
      "A Peer needs either a 'conn =>' or a 'route =>' at construction time"
  }

  if ($self->type eq 'TS' && $self->type_version == 6) {
    ## TS6 Peers need a SID.
    confess "A TS6 IRC::Peer needs a 'sid =>' at construction time"
      unless $self->has_sid;
  }
}


has 'casemap' => (
  ## For use with ->lower / ->upper; ascii should do
  lazy    => 1,
  is      => 'ro',
  default => sub { 'ascii' },
);
with 'IRC::Toolkit::Role::CaseMap';

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

has 'sid' => (
  ## SIDs for (->type eq 'TS' && ->type_version == 6) peers
  lazy      => 1,
  is        => 'ro',
  isa       => Str,
  writer    => 'set_sid',
  predicate => 'has_sid',
  ## FIXME BUILD should make sure we have a sid() if needed
);

has 'type' => (
  lazy   => 1,
  is     => 'ro',
  isa    => Str,
  writer => 'set_type',
  ## FIXME need an authoritative types list and a Moo type for same
  default => sub { 'TS' },
);

has 'type_version' => (
  lazy    => 1,
  is      => 'ro',
  isa     => Defined,
  writer  => 'set_type_version',
  default => sub { '6' },
);

has '_capabs' => (

);


## FIXME methods  to add/del ->linked() peers ?

1;
