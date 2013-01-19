package IRC::Server::Pluggable::IRC::Peers;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable qw/
  Types
  Utils
/;

use Scalar::Util 'weaken';

use namespace::clean -except => 'meta';


has '_peers' => (
  lazy    => 1,
  is      => 'ro',
  writer  => '_set_peers',
  default => sub { {} },
);

has '_peers_by_sid' => (
  lazy    => 1,
  is      => 'ro',
  default => sub { {} },
);

has '_peers_by_wheelid' => (
  lazy    => 1,
  is      => 'ro',
  default => sub { {} },
);

sub add {
  my ($self, $peer) = @_;

  confess "$peer is not a IRC::Server::Pluggable::IRC::Peer"
    unless is_Object($peer)
    and $peer->isa('IRC::Server::Pluggable::IRC::Peer');

  my $s_name = lc( $peer->name );

  $self->_peers->{$s_name} = $peer;

  if ($peer->has_sid) {
    $self->_peers_by_sid->{ $peer->sid } = $peer;
    weaken $self->_peers_by_sid->{ $peer->sid };
  }

  ## Only local peers should have a _peers_by_wheelid entry:
  if ($peer->has_conn) {
    $self->_peers_by_wheelid->{ $peer->conn->wheel_id } = $peer;
    weaken($self->_peers_by_wheelid->{ $peer->conn->wheel_id });
  }

  $peer
}

sub list_local_peers {
  my ($self) = @_;
  values %{ $self->_peers_by_wheelid }
}

sub as_array {
  my ($self) = @_;
  values %{ $self->_peers }
}

sub by_id {
  my ($self, $id) = @_;

  confess "by_id() called with no ID specified"
    unless defined $id;

  $self->_peers_by_wheelid->{$id}
}

sub by_name {
  my ($self, $s_name) = @_;

  confess "by_name() called with no server specified"
    unless defined $s_name;

  $self->_peers->{ lc($s_name) }
}

sub del {
  my ($self, $s_name) = @_;

  confess "del() called with no peer specified"
    unless defined $s_name;

  if (my $peer = delete $self->_peers->{ lc($s_name) }) {
    delete $self->_peers_by_wheelid->{ $peer->conn->wheel_id }
      if $peer->has_conn;
    delete $self->_peers_by_sid->{ $peer->sid }
      if $peer->has_sid;

    return $peer
  }
}

sub matching {
  my ($self, $mask) = @_;

  my @matches;
  for my $p_name (keys %{ $self->_peers }) {
    my $this_peer = $self->_peers->{$p_name};

    push @matches, $this_peer
      if matches_mask( $mask, $this_peer->name, 'ascii' );
  }

  wantarray ? @matches : @matches ? \@matches : ()
}


1;
