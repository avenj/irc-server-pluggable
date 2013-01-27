package IRC::Server::Pluggable::Protocol::Role::Version;

use 5.12.1;
use Carp;

use strictures 1;

use Moo::Role;
use IRC::Server::Pluggable qw/
  IRC::Event
/;


use namespace::clean;


with 'IRC::Server::Pluggable::Role::Interface::IRCd';
requires qw/
  protocol_dispatch
  equal
/;


sub __version_send_isupport {
  my ($self, $target) = @_;
  ## FIXME
  $self->send_to_targets(
    event => ev(
      command => '005',
      prefix  => $self,
      params  => [ 'HI, I suck and have no ISUPPORT yet' ],
    ),
    targets => [ $target ],
  );
}

sub __version_send_version {
  my ($self, $target) = @_;
  ## FIXME
  $self->send_to_targets(
    event => ev(
      command => '351',
      prefix  => $self,
      params  => [ $self->version_string ],
    ),
    targets => [ $target ],
  );
}


sub cmd_from_client_version {
  my ($self, $conn, $event, $user) = @_;

  my $server_name = $self->config->server_name;

  if (@{ $event->params }) {
    my $first = $event->params->[0];
    my $peer  = ( $self->peers->matching($first) )[0];
    unless (defined $peer) {
      ## No such server.
      $self->send_numeric( 402 =>
        prefix => $self,
        target => $user,
        params => [ $event->params->[0] ],
      );
      return
    }

    unless ( $self->equal($server_name, $peer->name) ) {
      ## Not us; relay.
      $self->send_to_targets(
        event => ev(
          prefix  => $user,
          command => 'VERSION',
          params  => [ $peer->name ],
        ),
        targets => [ $peer ],
        ## FIXME do we need to tweak options => at all ?
      );
      return
    }
  }

  ## Us.
  $self->__version_send_isupport($user);
  $self->__version_send_version($user);
}


sub cmd_from_peer_version {
  ## FIXME new send iface
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
