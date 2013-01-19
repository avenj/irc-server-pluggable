package IRC::Server::Pluggable::Protocol::Role::Send;

=pod

=head1 NAME

IRC::Server::Pluggable::Protocol::Role::Send

=head1 SYNOPSIS

Provides:

  FIXME

=head1 DESCRIPTION

Send/relay methods consumed by a Protocol.

See L<IRC::Server::Pluggable::Protocol>.

=cut


use 5.12.1;
use Carp;
use Moo::Role;
use strictures 1;

use Scalar::Util 'blessed';

use IRC::Server::Pluggable qw/
  IRC::Event
  Types
/;

use namespace::clean;

requires qw/
  config
  dispatcher
  numeric
/;


### FIXME should sendq management live here... ?

sub __send_retrieve_route {
  my ($self, $peer_name_or_obj) = @_;
  if ( blessed($peer_name_or_obj) ) {
    ## Peer obj.
    return $peer_name_or_obj->route
  }
  ## Name or route ID, we hope.
  return $self->peers->by_name($peer_name_or_obj) || $peer_name_or_obj    
}

sub __send_peer_correct_self_prefix {
  my ($self, $peer) = @_;
  ## Get correct prefix for messages we are sending to a local peer.
  # FIXME Move me out to a generic Peers role, make public?
  # Subclasses should be able to override to provide other prefixes
  if ($peer->type eq 'TS') {
    return $self->config->sid
      if $peer->type_version == 6
  }
  $self->config->server_name
}


=pod

=head2 send_to_local_peer

  $proto->send_to_local_peer(
    event => $event_obj,
    peer  => $peer_obj,
    except => $origin_peer,
  );

Relay to a single next-hop peer. Sugar for L</send_to_local_peers>; parameters
documented there also apply here.

=cut

sub send_to_local_peer {
  my ($self, %opts) = @_;
  confess "Expected 'peer =>'" unless $opts{peer};
  my $peer = delete $opts{peer};
  $self->send_to_local_peers(
    peers => [ $peer, ($opts{peers} ? @{ $opts{peers} } : ())  ],
    %opts
  )
}


=pod

=head2 send_to_local_peers

  ## Relay to all local peers:
  $proto->send_to_local_peers(
    event => {
      ## $self translated to our server name or SID:
      prefix  => $self,
      command => 'frobulate',
      ## $user translated to user's nickname or UID:
      params  => [ $user ],
    },
  );

  ## Relay to all local peers except one:
  $proto->send_to_local_peers(
    event  => $event_obj,
    except => $origin_peer,
  );

  ## Relay to a specific peer/set of peers:
  $proto->send_to_local_peers(
    event  => $event_obj,
    peers  => [ @peer_objs ],
  );

Basic traffic relay.

Does TS6 ID translation. If the B<nick_only> option is passed, user objects
will be translated to either a nickname or UID (depending on the remote peer
type); by default, they are translated to either a full C<nick!user@host> or
UID.

=cut

sub send_to_local_peers {
  my ($self, %opts) = @_;
  my $event;
  confess "Expected at least an 'event =>' parameter"
    unless ($event = delete $opts{event}) and ref $event;

  my %except_route;

  if ($opts{except}) {
    if (ref $opts{except} eq 'ARRAY') {
      %except_route = map {; $self->__send_retrieve_route($_)  => 1 }
                      @{ $opts{except} };
    } else {
      $except_route{ $self->__send_retrieve_route($_) } = 1
    }
  }

  ## FIXME option to send only to peers with a certain CAPAB

  my $use_full = $opts{nick_only} || 1;

  my @local_peers = $opts{peers} ? @{ $opts{peers} }
    : $self->peers->list_local_peers;

  my $as_hash = %$event;
  my $sent; 
  LPEER: for my $peer (@local_peers) {
    my $route = $peer->route;
    next LPEER if $except_route{$route};

    ## Automagic $self / IRC::User / IRC::Peer prefix translation:
    if (blessed $as_hash->{prefix}) {
      CASE_FROM: { 
        my $pfix = $as_hash->{prefix};

        if ($pfix eq $self || $pfix eq 'localserver') {
          ## Self talking to peer.
          $as_hash->{prefix} = $self->__send_peer_correct_self_prefix($peer);
          last CASE_FROM
        }
        if ($pfix->isa('IRC::Server::Pluggable::IRC::User')) {
          ## User relaying to peer.
          $as_hash->{prefix} = $self->uid_or_nick($pfix, $peer);
          last CASE_FROM
        }
        if ($pfix->isa('IRC::Server::Pluggable::IRC::Peer')) {
          ## Peer relaying to peer.
          $as_hash->{prefix} = $peer->has_sid ? $pfix->sid : $pfix->name;
          last CASE_FROM
        }

        confess "Do not know how to handle blessed prefix $pfix"
      } # CASE_FROM
    }

    ## Automagically uid_or_nick/uid_or_full any User/Peer objs in params:
    $as_hash->{params} = [
      map {;
        my $param = $_;

        if (blessed $param) {
          ( $param = $use_full ? $self->uid_or_full($param, $peer)
                      :  $self->uid_or_nick($param, $peer) )
            if $param->isa('IRC::Server::Pluggable::IRC::User');

          ( $param = $param->has_sid ? $param->sid : $param->name )
            if $param->isa('IRC::Server::Pluggable::IRC::Peer');
        }

        $param
      } @{ $as_hash->{params} || [] }
    ];

    $self->dispatcher->to_irc( ev(%$as_hash), $route );
    ++$sent
  } # LPEER

  $sent
}


=pod

=head2 send_to_targets

FIXME

=cut

sub send_to_targets {
  ## Handle relaying to arbitrary targets.
  ## $event should have a translatable prefix
  ## See send_to_local_peers
  my ($self, $event, @targets) = @_;
  confess "Expected an IRC::Event or compatible HASH"
    unless ref $event;

  TARGET: for my $target (@targets) {
    confess "Expected an IRC::User or IRC::Peer"
      unless blessed $target;

    if ($target->has_conn) {
      if ($target->isa('IRC::Server::Pluggable::IRC::User') ) {
        ## Local user.
        ## FIXME do we need to do any TS translation at all?
        $self->dispatcher->to_irc( $event, $target );
        next TARGET
      } elsif ($target->isa('IRC::Server::Pluggable::IRC::Peer') ) {
        ## Local peer.
        $self->send_to_local_peer(
          event => $event,
          peer  => $target,
        );
      }
    }

    my $next_hop = $target->route;
    my $peer = $self->peers->by_id($next_hop);
    unless ($peer) {
      carp "Cannot relay to nonexistant peer (route ID $next_hop)";
      next TARGET
    }

    $self->send_to_local_peer(
      event => $event,
      peer  => $peer,
    );
  }
}


=pod

=head2 send_numeric

  $proto->send_numeric( $numeric =>
    target => $user_obj,
    routes => [ @routes ],
    params => [ @extra_params ],
  );

=cut

## FIXME does TS6 send uid_or_nick with peer-directed numerics ?
sub send_numeric {
  ## send_numeric(  $numeric,
  ##   target => ...,
  ##   routes => \@routes,
  ## );
  ## Optionally pass prefix / params
  my ($self, $numeric, %params) = @_;
  $params{lc $_} = delete $params{$_} for keys %params;

  confess "Expected a numeric and at least 'target' and 'routes' params"
    unless defined $params{target}
    and    defined $params{routes};

  my @routes = ref $params{routes} eq 'ARRAY' ?
                 @{ $params{routes} }
                 : $params{routes} ;

  my $output = $self->numeric->to_hash( $numeric,
    target => $params{target},

    ## Default to our server name.
    ## FIXME ..or SID? check rb
    prefix => (
      $params{prefix} ?
        $params{prefix} : $self->config->server_name
    ),

    params => (
      ref $params{params} eq 'ARRAY' ?
        $params{params} : [ $params{params}||() ]
    ),
  );

  $self->dispatcher->to_irc( $output, @routes )
}



##### FIXME deprecated #####

sub send_to_route  { shift->send_to_routes(@_) }
sub send_to_routes {
  my ($self, $output, @ids) = @_;
  carp "send_to_routes is deprecated";
  ## FIXME
  ##  Deprecate in favor of send_to_targets, move to low-level api
  ##  we should deal only in objects at higher layers, leave ->route for
  ##  lowlevel operations
  unless (ref $output && @ids) {
    confess "send_to_routes() received insufficient params";
    return
  }

  $self->dispatcher->to_irc( $output, @ids )
}

sub send_to_routes_now {
  my ($self, $output, @ids) = @_;
  carp "send_to_routes_now is deprecated";
  unless (ref $output && @ids) {
    confess "send_to_routes_now() received insufficient params";
    return
  }

  $self->dispatcher->to_irc_now( $output, @ids )
}

 ##########################




1;

=pod

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
