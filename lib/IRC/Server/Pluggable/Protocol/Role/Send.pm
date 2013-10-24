package IRC::Server::Pluggable::Protocol::Role::Send;
use Defaults::Modern;


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


method _send_retrieve_route ($peer_name_or_obj) {
  ## Return a route ID for given peer name or object.
  ## If we can't locate one, return whatever we were passed in --
  ## the excepted route map should just not care.
  if (blessed $peer_name_or_obj) {
    # Assume we were passed a peer obj.
    return $peer_name_or_obj->route
  }
  if (my $peer_obj = $self->peers->by_name($peer_name_or_obj)) {
    return $peer_obj->route
  } else {
    return $peer_name_or_obj
  }
}

method _send_peer_correct_self_prefix ($peer) {
  ## Get correct prefix for messages we are sending to a local peer.
  return $self->config->sid 
    if  $peer->type eq 'TS' 
    and $peer->type_version == 6;
  $self->config->server_name
}

method _send_event_buffer (Object $dest, Object $event) {
  ## FIXME
  ##  like ratbox send_linebuf,
  ##  take a dest obj, check $dest->sendq_buf (need a Role for this
  ##  for Users and Peers),
  ##  issue a sendq exception if needed (see get_sendq),
  ##  else append line to ->sendq_buf (update statistics..?)
  ##  and call a ->_send_queued_events($dest) if $dest->sendq_buf > 0
  ## FIXME saner to deal in queued events then ->send_to_routes
  ##  use bytes::length of raw str for sendq purposes ?
  ##  
}

method _send_queued_events (Object $dest) {
  ## FIXME
  ##  see ratbox send_queued ?
  ##  need a User / Peer role for sendq bits
  ##  probably also a timer to check?
  ##    pool of weak refs to dest routes with pending sendq?
}

method _send_parse_identifiers (
  :$event,
  (PeerObj | Undef) :$peer  = undef,
  :$local = 0,
  :$prefix_nick_only = undef,
  :$params_nick_only = undef
) {
  ## Look for $user or $peer objects in an Event.
  ## Translate depending on destination Peer type.
  ## (eg. speak TS6 to TS6 servers, otherwise use names)
  ## FIXME this should probably be optimized ...
  ##   move all message construction bits out to their own methods,
  ##   provide flexible methods to retrieve dest routes,
  ##   provide simpler send methods?

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
        : $self->_send_peer_correct_self_prefix($peer);

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


method send_to_servers (
  Ref :$event,

  :$except = undef,
  :$caps   = undef,
  :$nocaps = undef,
) {
  ## ->send_to_servers(
  ##   event => $event,
  ## # optional:
  ##    except => [ @objs ],
  ##    caps   => [ @wanted_caps ],
  ##    nocaps => [ @excluded_caps ],
  ## )

}

## FIXME  sendq needs a timer loop


## FIXME deprecate eventsets? else we need support here

method send_to_one (
  Ref :$event,
  (UserObj | PeerObj) :$target,
) {

  # if $target is ours, we can shove this on the object's send buf
  # else we need the next-hop peer obj:
  my $dest = $self->object_is_local($target) ?
    $target : $self->peers->by_id( $target->route );

  #  FIXME global & return if trying to send to self

  $dest->sendq_buf->push( $event );
}

method send_to_one_prefix (
  Ref :$event,
  (UserObj | PeerObj) :$target,
  (UserObj | PeerObj) :$source,
) {

  # FIXME like send_to_one but with ID translation
  # FIXME global and return if trying to send to self

  my $dest = $self->object_is_local($target) ?
    $target : $self->peers->by_id( $target->route );

  my $parsed_ev = $self->_send_id_translate(
    event  => $event,
    target => $target,
    source => $source,
  );

  $dest->sendq_buf->push( $parsed_ev );
}

method send_to_one_numeric (
  # FIXME
) {
  # FIXME
}

method send_to_anywhere (
  # FIXME
) {
  # FIXME see ratbox send.c sendto_anywhere
}






## FIXME send_to_targets is wrong / needs reworked/removed ...
##   - needs to be able to support messages without prefix
##   - needs more consistent interface
##   - see what else ratbox send.c does 
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
          $self->_send_parse_identifiers(
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
        $prefix = $self->_send_peer_correct_self_prefix($peer);
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
        map {; $self->_send_retrieve_route($_)  => 1 } @$except;
    } else {
      $except_route{ $self->_send_retrieve_route($_) } = 1
    }
  }

  ## FIXME option to send only to peers with a certain CAPAB
  ##  Needs IRC::Peer tweak

  my @local_peers = $peers ? @$peers : $self->peers->list_local_peers;
  my $sent; 
  LPEER: for my $peer (@local_peers) {
    my $route = $peer->route;
    next LPEER if $except_route{$route};

    my $parsed_ev = $self->_send_parse_identifiers(
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


method send_to_routes ( Ref $output, @ids ) {
  confess "send_to_routes() received insufficient params"
    unless @ids;
  $self->dispatcher->to_irc( $output, @ids )
}
{ no warnings 'once'; *send_to_route = *send_to_routes }


1;

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

=head2 send_numeric

  $proto->send_numeric( $numeric =>
    target => $user_obj,
    routes => [ @routes ],
    params => [ @extra_params ],
  );

Create and send a predefined numeric-type error response; see
L<IRC::Server::Pluggable::IRC::Numerics>.

=head2 send_to_routes

  $proto->send_to_routes( $event, @routes );

B<send_to_routes> / B<send_to_route> are low-level Protocol message
dispatchers; these bridge the Dispatcher layer and are used by the 
higher-level methods detailed above.


=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
