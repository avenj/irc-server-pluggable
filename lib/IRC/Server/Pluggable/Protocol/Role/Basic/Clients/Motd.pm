package IRC::Server::Pluggable::Protocol::Role::Basic::Clients::Motd;

use Moo::Role;
use strictures 1;


use namespace::clean -except => 'meta';

requires qw/
  config

  numeric

  users

  send_to_routes
/;

sub cmd_from_peer_motd {
  my ($self, $conn, $event) = @_;

  ## Remote user asked for MOTD.

  $self->cmd_from_client_motd($conn, $event)
}

sub cmd_from_client_motd {
  my ($self, $conn, $event) = @_;

  my $nickname = $event->prefix;
  my $user     = $self->users->by_name($nickname);
  my $server   = $self->config->server_name;

  ## FIXME needs to check args and route to remote peer
  ##  if one specified
  ##  - get first arg
  ##  - chk against $server case-insensitively
  ##  - chk if we have this peer
  ##  - 402 if we don't know this peer
  ##  - relay if we do
  ## Requires sorting out current Peers clusterfuck

  ## 422 if no MOTD
  unless ($self->config->has_motd) {
    my $output = $self->numeric->to_hash( 422,
      prefix => $server,
      target => $nickname,
    );

    $self->send_to_routes( $output, $user->route );

    return 1
  }

  $self->send_to_routes(
    {
      prefix  => $server,
      command => '375',
      params  => [ $nickname, "- $server Message of the day - "],
    },
    $user->route
  );

  my @motd = @{ $self->config->motd };

  for my $line (@motd) {
    $self->send_to_routes(
      {
        prefix  => $server,
        command => '372',
        params  => [ $nickname, "- $line" ],
      },
      $user->route
    );
  }

  $self->send_to_routes(
    {
      prefix  => $server,
      command => '376',
      params  => [ $nickname, "End of MOTD command" ],
    },
    $user->route
  );

  1
}

1;

=pod

=head1 NAME

IRC::Server::Pluggable::Protocol::Role::Basic::Clients::Motd

=head1 SYNOPSIS

  Handles:
    cmd_from_client_motd
    cmd_from_peer_motd

=head1 DESCRIPTION

A L<Moo::Role> adding 'MOTD' command handlers to a
L<IRC::Server::Pluggable::Protocol::Base> subclass.

Usually consumed by
L<IRC::Server::Pluggable::Protocol::Role::Basic::Clients> via
L<IRC::Server::Pluggable::Protocol>

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
