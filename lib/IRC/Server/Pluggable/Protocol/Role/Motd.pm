package IRC::Server::Pluggable::Protocol::Role::Motd;
use Defaults::Modern;


use IRC::Server::Pluggable qw/
  IRC::Event
/;


use Moo::Role;
with 'IRC::Server::Pluggable::Role::Interface::IRCd';

method cmd_from_client_motd ($conn, $event, $user) {
  my $nickname = $user->nick;
  my $server   = $self->config->server_name;

  REMOTE: {
    if (@{ $event->params }) {
      my $request_peer = $event->params->[0];

      if (uc($request_peer) eq uc($server)) {
        ## This is us. Continue our normal MOTD dispatch.
        last REMOTE
      }

      my $peer;
      unless ($peer = $self->peers->by_name($request_peer) ) {
        ## Don't know this peer. Send 402
        $self->send_numeric( 402 => 
          prefix => $self,
          target => $user,
          params => [ $peer->name ],
        );
        return
      }

      ## Relayed elsewhere.
      $self->send_to_targets(
        event => ev(
          prefix  => $user,
          command => 'MOTD',
          params  => [ $peer->name ],
        ),
        targets => [ $peer ],
      );
      return 1
    }
  }  ## REMOTE

  unless ($self->config->motd->has_any) {
    $self->send_numeric( 422 =>
      prefix => $self,
      target => $user,
    );
    return 1
  }

  my @outgoing = ev(
    prefix  => $self,
    command => '375',
    params  => [ $user, "- $server Message of the day - "],
  );

  push @outgoing, ev(
      prefix  => $self,
      command => '372',
      params  => [ $user, "- ".$_ ],
  ) for $self->config->motd->all;

  $self->send_to_targets(
    event  => $_,
    target => $user,
  ) for @outgoing, ev(
    prefix => $self,
    command => '376',
    params  => [ $user, "End of MOTD command" ],
  );
 
  1
}

method cmd_from_peer_motd ($conn, $event) {
  ## Remote user asked for MOTD.
  my $user = $self->users->by_name( $event->prefix ) || return;

  $self->yield( protocol_dispatch => 
    cmd_from_client_motd => $conn, $event, $user
  )
}


1;

=pod

=head1 NAME

IRC::Server::Pluggable::Protocol::Role::TS::Clients::Motd

=head1 SYNOPSIS

  Handles:
    cmd_from_client_motd
    cmd_from_peer_motd

=head1 DESCRIPTION

A L<Moo::Role> adding 'MOTD' command handlers to a
L<IRC::Server::Pluggable::Protocol::Base> subclass.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
