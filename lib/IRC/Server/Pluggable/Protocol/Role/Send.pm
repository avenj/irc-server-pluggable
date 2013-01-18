package IRC::Server::Pluggable::Protocol::Role::Send;

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

sub send_to_local_peer {
  my ($self, %opts) = @_;
  confess "Expected 'peer =>'" unless $opts{peer};
  my $peer = delete $opts{peer};
  $self->send_to_local_peers(
    peers => [ $peer, ($opts{peers} ? @{ $opts{peers} } : ())  ],
    %opts
  )
}

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

  my $use_full = $opts{nick_only} || 1;

  my @local_peers = $opts{peers} ? @{ $opts{peers} }
    : $self->peers->list_local_peers;

  my $as_hash = %$event;
  my $sent; 
  LPEER: for my $peer (@local_peers) {
    my $route = $peer->route;
    next LPEER if $except_route{$route};

    if (blessed $as_hash->{prefix}) {
      my $pfix = $as_hash->{prefix};
      CASE_FROM: {
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

    $self->send_to_routes( ev(%$as_hash), $route );
    ++$sent
  } # LPEER

  $sent
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

sub send_to_targets_from {
  ## FIXME $from irrelevant now per new send_to_local_peers
  my ($self, $from, $event, @targets) = @_;
  confess "Expected an IRC::Event or compatible HASH"
    unless ref $event;

  TARGET: for my $target (@targets) {
    confess "Expected an IRC::User or IRC::Peer"
      unless blessed $target;

    if ($target->has_conn) {
      if ($target->isa('IRC::Server::Pluggable::IRC::User') ) {
        ## Local user.
        ## FIXME do we need to do any TS translation at all?
        $self->send_to_routes( $event, $target->route );
        next TARGET
      } elsif ($target->isa('IRC::Server::Pluggable::IRC::Peer') ) {
        ## Local peer.
        $self->send_to_local_peer(
          event => $event,
          peer  => $target,
          from  => $from,
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
      from  => $from,
    );
  }
}

sub send_to_route  { shift->send_to_routes(@_) }
sub send_to_routes {
  my ($self, $output, @ids) = @_;
  ## FIXME
  ##  This should go away in favor of send_to_user & send_to_local_peers
  ##  send_to_user should do TS vs non-TS translation like send_to_local_peers
  ##  (or genericize to send_to_targets?)
  ##  if User obj:
  ##    * event directed at local or remote User
  ##    - if our user, relay direct
  ##    - if not our user, send_to_local_peer for next-hop peers
  ##  if Peer obj:
  ##    * event directed at local or remote Server
  ##    - send_to_local_peers for the next-hop peers
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
  unless (ref $output && @ids) {
    confess "send_to_routes_now() received insufficient params";
    return
  }

  $self->dispatcher->to_irc_now( $output, @ids )
}

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
    prefix => (
      $params{prefix} ?
        $params{prefix} : $self->config->server_name
    ),

    params => (
      ref $params{params} eq 'ARRAY' ?
        $params{params} : [ $params{params}||() ]
    ),
  );

  $self->send_to_routes( $output, @routes )
}


1;
