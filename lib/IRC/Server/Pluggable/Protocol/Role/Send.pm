package IRC::Server::Pluggable::Protocol::Role::Send;
use Defaults::Modern;

=pod

=head1 NAME

IRC::Server::Pluggable::Protocol::Role::Send

=head1 SYNOPSIS

Provides:

  send_to_targets
  send_numeric
  send_to_local_peers
  send_to_routes

=head1 DESCRIPTION

Send/relay methods consumed by a Protocol.

See L<IRC::Server::Pluggable::Protocol>.

=cut


use IRC::Server::Pluggable qw/
  IRC::Event
  Types
/;


use Moo::Role;
use namespace::clean;

requires qw/
  config
  dispatcher
  numeric
  peers
  users

  uid_or_nick
  uid_or_full
/;


### FIXME should sendq management live here... ?



method __send_retrieve_route ($peer_name_or_obj) {
  if (blessed $peer_name_or_obj) {
    ## Peer obj.
    return $peer_name_or_obj->route
  }
  $self->peers->by_name($peer_name_or_obj) || $peer_name_or_obj 
}

method __send_peer_correct_self_prefix ($peer) {
  ## Get correct prefix for messages we are sending to a local peer.
  return $self->config->sid 
    if  $peer->type eq 'TS' 
    and $peer->type_version == 6;
  $self->config->server_name
}

method __send_parse_identifiers (
  :$event,
  (PeerObj | Undef) :$peer  = undef,
  :$local = 0,
  :$prefix_nick_only = undef,
  :$params_nick_only = undef
) {
  ## Look for $user or $peer objects in an Event.
  ## Translate depending on Peer type.

  ## FIXME these opts need to be documented somewheres
  ## rework existing _local_peers iface/POD
  ##  wrt prefix/params replacement opts?

  unless ($peer) {
    confess "Expected either a 'peer =>' obj or 'local => 1'"
      unless $local;
    ## FIXME is this correct?
    $prefix_nick_only //= 0;
  }
  $prefix_nick_only //= 1;
  $params_nick_only //= 1;

  ## Automagic $self / IRC::User / IRC::Peer prefix translation:

  my %as_hash = %$event;

  CASE_FROM: for ($as_hash{prefix} || $self) { 
    last CASE_FROM unless blessed $_;

    if  ($_ == $self) {
    ## Self talking to local or peer.
      $as_hash{prefix} = $local ? 
        $self->config->server_name
        : $self->__send_peer_correct_self_prefix($peer);

      last CASE_FROM
    }

    if (is_UserObj $_) {
    ## User talking to local or peer.
      if ($local) {
        $as_hash{prefix} = $prefix_nick_only ? $_->nick : $_->full
      } else {
        $as_hash{prefix} = $prefix_nick_only ? 
          $self->uid_or_nick($_, $peer) : $self->uid_or_full($_, $peer)
      }

      last CASE_FROM
    }

    if (is_PeerObj $_) {
    ## Peer relaying to local or peer.
      if ($local) {
        $as_hash{prefix} = $_->name
      } else {
        $as_hash{prefix} = $peer->has_sid ? $_->sid : $_->name
      }

      last CASE_FROM
    }

    confess "Do not know how to handle blessed prefix $_"
  } # CASE_FROM

  ## Automagically uid_or_nick/uid_or_full any User/Peer objs in params:
  IDTRANS: for (@{ $as_hash{params} ||= [] }) {
    next IDTRANS unless blessed $_;
    $_ = 
      is_UserObj($_) ?
        $params_nick_only ?
          $self->uid_or_nick($_, $peer) : $self->uid_or_full($_, $peer)
      : is_PeerObj($_) ? 
          $_->has_sid ? 
            $_->sid : $_->name
      : $_
  }

  ev(%as_hash)
}



=pod

=head2 send_to_targets

  $proto->send_to_targets(
    event   => $ev,
    targets => [ @objects ],
    options => +{
      ## Passed to appropriate handler for target type:
      params_nick_only => 1,
    },
  );

## FIXME
 ... handle eventsets (build new evset from parsed events)?
     -> or just deprecate eventsets

=cut

method send_to_targets (Ref :$event, %opts) {
  ## Handle relaying to arbitrary targets.
  ## $event should have a translatable prefix
  ## See send_to_local_peers
  push @{ $opts{targets} }, delete $opts{target}
    if defined $opts{target};

  confess "Expected at least 'event =>' and 'targets =>' params"
    unless Scalar::Util::reftype $event eq 'HASH'
    and ref $opts{targets} eq 'ARRAY'; 

  my %extra = defined $opts{options} ? %{ $opts{options} } : ();

  TARGET: for my $target (@{ $opts{targets} }) {
    confess "Expected an IRC::User or IRC::Peer"
      unless blessed $target
      and $target->can('has_conn');

    if ($target->has_conn) {
      ## Local connect.

      if (is_UserObj $target) {
        ## Local user.
        $self->send_to_routes( 
          $self->__send_parse_identifiers(
            event => $event,
            local => 1,
            %extra,
          ),
          $target->route
        );
      } elsif (is_PeerObj $target) {
        ## Local peer.
        $self->send_to_local_peer(
          event => $event,
          peer  => $target,
          %extra,
        );
      } else {
        confess 
          "No clue how to dispatch target type @{[ref $target]} ($target)"
      }

      next TARGET
    }

    ## Remote peer or user.
    ## FIXME check TS6 translation behavior, pass opts
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
  }  # TARGET
}


=pod

=head2 send_numeric

  $proto->send_numeric( $numeric =>
    target => $user_obj,
    routes => [ @routes ],
    params => [ @extra_params ],
  );

Create and send a predefined numeric-type error response; see
L<IRC::Server::Pluggable::IRC::Numerics>.

=cut

method send_numeric (
  Int     :$numeric,
  UserObj :$target,
  :$prefix = undef,
  :$params = undef,
) {

  if ($target->has_conn) {
    ## Local user. Do prefix conversion.
    if (defined $prefix) {
      if (blessed $prefix) {
        $prefix = $prefix == $self ? 
          $self->config->server_name : $prefix->name;
      }
    } else {
      $prefix = $self->config->server_name
    }

    $self->send_to_routes(
      $self->numeric->to_hash(
        target => $target,
        prefix => $prefix,
        params => ( 
          ref $params eq 'ARRAY' ?
            $params : [ $params // () ]
        ),
      ), 
      $target
    );
  } else {
    ## Remote user.
    ## We want name/SID of self or 'prefix =>' peer
    ## + numeric + target UID or nick
    my $next_hop  = $target->route;
    my $peer      = $self->peers->by_id($next_hop);
    NPREFIX: {
      unless (defined $prefix) {
        ## Assume from local.
        $prefix = $self->__send_peer_correct_self_prefix($peer);
        last NPREFIX
      }

      if (blessed $prefix) {
        if ($peer->has_sid && $prefix->has_sid) {
          $prefix->sid
        } else {
          $prefix = $prefix->name
        }
        last NPREFIX
      }
    }

    $params = [ $params // () ] unless ref $params eq 'ARRAY';
    my $endpoint = $self->uid_or_nick($target, $peer);
    $self->send_to_routes(
      +{
        command => $numeric,
        prefix  => $prefix,
        params  => [ $endpoint, @$params ],
      },
      $target
    );
  }

  1
}


=pod

=head2 send_to_local_peer

  $proto->send_to_local_peer(
    event => $event_obj,
    peer  => $peer_obj,
    except => $origin_peer,
  );

Relay to a single next-hop peer. Sugar for L</send_to_local_peers>; options
documented there also apply to this method.

=cut

method send_to_local_peer (
  :$peer,
  :$peers = undef,
  %opts
) {
  $self->send_to_local_peers(
    peers => [ $peer, ($peers ? @$peers : ()) ],
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

method send_to_local_peers (
  Ref :$event,
  :$except = undef,
  (ArrayRef | Undef) :$peers = undef,
  :$nick_only = 0,
) {

  my %except_route;
  if ($except) {
    if (ref $except eq 'ARRAY') {
      %except_route = 
        map {; $self->__send_retrieve_route($_)  => 1 } @$except;
    } else {
      $except_route{ $self->__send_retrieve_route($_) } = 1
    }
  }

  ## FIXME option to send only to peers with a certain CAPAB
  ##  Needs IRC::Peer tweak

  my @local_peers = $peers ? @$peers : $self->peers->list_local_peers;
  my $sent; 
  LPEER: for my $peer (@local_peers) {
    my $route = $peer->route;
    next LPEER if $except_route{$route};

    my $parsed_ev = $self->__send_parse_identifiers(
      peer  => $peer, 
      event => $event,
      ## FIXME needs to use newer iface
      nick_only => $nick_only,
    );
    $self->send_to_routes( $parsed_ev, $route );

    ++$sent
  } # LPEER

  $sent
}


=pod

=for Pod::Coverage send_to_route

=head2 send_to_routes

  $proto->send_to_routes( $event, @routes );

B<send_to_routes> / B<send_to_route> are low-level Protocol message
dispatchers; these bridge the Dispatcher layer and are used by the 
higher-level methods detailed above.

=cut

method send_to_routes ( Ref $output, @ids ) {
  confess "send_to_routes() received insufficient params"
    unless @ids;
  $self->dispatcher->to_irc( $output, @ids )
}
{ no warnings 'once'; *send_to_route = *send_to_routes }


1;

=pod

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
