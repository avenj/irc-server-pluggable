package IRC::Server::Pluggable::Protocol::Role::Basic::Clients::Motd;

use Moo::Role;
use strictures 1;


use namespace::clean -except => 'meta';


sub cmd_from_client_motd {
  my ($self, $conn, $event) = @_;

  my $target_nick = $event->prefix;
  my $target_user = $self->users->by_name($target_nick);
  my $server_name = $self->config->server_name;

  ## FIXME needs to check args and route to remote peer
  ##  if one specified
  ##  - get first arg
  ##  - chk against $server_name case-insensitively
  ##  - chk if we have this peer
  ##  - 402 if we don't know this peer
  ##  - relay if we do

  ## 422 if no MOTD
  unless ($self->config->has_motd) {
    my $output = $self->numeric->to_hash( 422,
      prefix => $server_name,
      target => $target_nick,
    );

    $self->send_to_routes( $output, $target_user->route );

    return 1
  }

  $self->send_to_routes(
    {
      prefix  => $server_name,
      command => '375',
      params  => [ $target_nick, "- $server_name Message of the day - "],
    },
    $target_user->route
  );

  my @motd = @{ $self->config->motd };

  for my $line (@motd) {
    $self->send_to_routes(
      {
        prefix  => $server_name,
        command => '372',
        params  => [ $target_nick, "- $line" ],
      },
      $target_user->route
    );
  }

  $self->send_to_routes(
    {
      prefix  => $server_name,
      command => '376',
      params  => [ $target_nick, "End of MOTD command" ],
    },
    $target_user->route
  );

  1
}

1;
