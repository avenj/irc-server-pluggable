package IRC::Server::Pluggable::Protocol::Role::Version;

use 5.12.1;
use Carp;

use strictures 1;

use Moo::Role;
use IRC::Server::Pluggable qw/
  IRC::EventSet
/;


use namespace::clean;


with 'IRC::Server::Pluggable::Role::Interface::IRCd';
requires qw/
  protocol_dispatch
  equal
/;


sub r_proto_build_isupport {
  my ($self, $eventset) = @_;
  ## 005 ISUPPORT
  $eventset = IRC::Server::Pluggable::IRC::EventSet->new
    unless defined $eventset;

  ## FIXME
  $eventset->push(
    {
      command => '005',
      prefix  => $self->config->server_name,
      params  => [ 'HI, I suck and have no ISUPPORT yet.' ],
    },
  );

  $eventset
}

sub r_proto_build_version {
  my ($self, $eventset) = @_;
  ## 351 VERSION
  $eventset = IRC::Server::Pluggable::IRC::EventSet->new
    unless defined $eventset;

  ## FIXME current composed version is braindead
  $eventset->push(
    {
      command => '351',
      prefix  => $self->config->server_name,
      params  => [ $self->version_string ],
    },
  );

  $eventset
}


sub cmd_from_client_version {
  my ($self, $conn, $event, $user) = @_;

  my $server_name = $self->config->server_name;

  if (@{ $event->params }) {
    my $first = $event->params->[0];
    my $peer  = ( $self->peers->matching($first) )[0];
    unless (defined $peer) {
      ## No such server.
      $self->send_to_routes(
        $self->numeric->as_hash( 402,
          target => $user->nick,
          prefix => $server_name,
          params => [ $event->params->[0] ],
        ),
        $user->route
      );
    }

    unless ( $self->equal($server_name, $peer->name) ) {
      ## Not us; relay.
      $self->send_to_routes(
        {
          prefix  => $user->nick,
          command => 'VERSION',
          params  => $peer->name,
        },
        $peer->route
      );
      return
    }
  }

  my $version_set  = $self->r_proto_build_version;
  my $isupport_set = $self->r_proto_build_isupport($version_set);
  $self->send_to_routes( $isupport_set, $user->route );
}


sub cmd_from_peer_version {
  my ($self, $conn, $event, $peer) = @_;

  my $dest = $event->params->[0];
  my $server_name = $self->config->server_name;

  if (!defined $dest || $self->equals($dest, $server_name)) {
    my $user = $self->users->by_name( $event->prefix ) || return;
    $event->set_params([]);
    $self->protocol_dispatch( 'cmd_from_client_version', 
      $conn, $event, $user 
    );
  } else {
    my $peer = $self->peers->by_name($dest);

    unless (defined $peer) {
      ## FIXME unknown server? should we just drop it?
      ##  check hyb
      return
    }
    $self->send_to_routes( $event, $peer->route );
  }
}



1;
