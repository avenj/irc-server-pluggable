package IRC::Server::Pluggable::Protocol::Role::Motd;

use Moo::Role;
use strictures 1;

use IRC::Server::Pluggable qw/
  IRC::Event
/;

use namespace::clean;

with 'IRC::Server::Pluggable::Role::Interface::IRCd';


sub cmd_from_client_motd {
  my ($self, $conn, $event, $user) = @_;

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

  unless ($self->config->has_motd) {
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

  my @motd = @{ $self->config->motd };
  push @outgoing, ev(
      prefix  => $self,
      command => '372',
      params  => [ $user, "- ".$_ ],
  ) for @{ $self->config->motd };

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

sub cmd_from_peer_motd {
  my ($self, $conn, $event) = @_;
  ## Remote user asked for MOTD.
  my $user = $self->users->by_name( $event->prefix ) || return;

  $self->yield( 'protocol_dispatch' => 'cmd_from_client_motd',
    $conn, $event, $user
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
