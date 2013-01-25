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
  $self->peers->by_name($peer_name_or_obj) || $peer_name_or_obj    
}

sub __send_peer_correct_self_prefix {
  my ($self, $peer) = @_;
  ## Get correct prefix for messages we are sending to a local peer.
  # FIXME Move me out to a generic Peers role, make public?
  # Subclasses should be able to override to provide other prefixes
  return $self->config->sid 
    if  $peer->type eq 'TS' 
    and $peer->type_version == 6;
  $self->config->server_name
}

sub __send_parse_identifiers {
  my ($self, %opts) = @_;
  ## Look for $user or $peer objects in an Event.
  ## Translate depending on Peer type.
  ## FIXME make public, document?

  my $as_hash  = %{ $opts{event}  || confess "Expected an 'event =>'" };

  ## FIXME document, rework existing _local_peers iface/POD
  ##  wrt prefix/params replacement opts

  my $peer = $opts{peer};
  unless (blessed $peer) {
    confess "Expected either a 'peer =>' obj or 'local => 1'"
      unless $opts{local};
    $opts{prefix_nick_only} //= 0;
  }
  $opts{prefix_nick_only} //= 1;
  $opts{params_nick_only} //= 1;

  ## Automagic $self / IRC::User / IRC::Peer prefix translation:
  if (blessed $as_hash{prefix}) {
      CASE_FROM: { 
        my $pfix = $as_hash{prefix};

        if  ($pfix eq $self || $pfix eq 'localserver') {
        ## Self talking to local or peer.
          $as_hash{prefix} = $opts{local} ?
            $self->config->server_name
            : $self->__send_peer_correct_self_prefix($peer);

          last CASE_FROM
        }

        if ($pfix->isa('IRC::Server::Pluggable::IRC::User')) {
        ## User talking to local or peer.
          if ($opts{local}) {
            $as_hash{prefix} = $opts{prefix_nick_only} ?
              $pfix->nick 
              : $pfix->full
          } else {
            $as_hash{prefix} = $opts{prefix_nick_only} ?
              $self->uid_or_nick($pfix, $peer) 
              : $self->uid_or_full($pfix, $peer)
          }

          last CASE_FROM
        }

        if ($pfix->isa('IRC::Server::Pluggable::IRC::Peer')) {
        ## Peer relaying to local or peer.
          if ($opts{local}) {
            $as_hash{prefix} = $pfix->name
          } else {
            $as_hash{prefix} = $peer->has_sid ? $pfix->sid : $pfix->name
          }

          last CASE_FROM
        }

        confess "Do not know how to handle blessed prefix $pfix"
      } # CASE_FROM
  }

  ## Automagically uid_or_nick/uid_or_full any User/Peer objs in params:
  ## FIXME needs to handle params_nick_only
  ## FIXME needs to be well-documented; consumers should be explicit if
  ##  necessary
  $as_hash{params} = [
    map {;
        my $param = $_;

        if (blessed $param) {
          ( $param = $self->uid_or_nick($param, $peer) )
            if $param->isa('IRC::Server::Pluggable::IRC::User');

          ( $param = $param->has_sid ? $param->sid : $param->name )
            if $param->isa('IRC::Server::Pluggable::IRC::Peer');
        }

        $param
      } @{ $as_hash{params} || [] }
  ];

  ev(%$as_hash)
}




=pod

=head2 send_to_targets

## FIXME
 ... optional per-target opts
   i.e. @targets = ( [ $target_obj, $opts_hash ] ) ?
   otherwise need named params so we can pass send opts
   (or force use of a specific method)
 ... pull in send-related bits from Messages?
 ... ideally other roles are primarily command handlers
     that use core logic found in the slimmest possible set
 ... handle eventsets (build new evset from parsed events)
 ... move up and document as primary send API

=cut

sub send_to_targets {
  ## Handle relaying to arbitrary targets.
  ## $event should have a translatable prefix
  ## See send_to_local_peers
  my ($self, %opts) = @_;
  my $event = $opts{event};
  confess "Expected at least 'event =>' and 'targets =>' params"
    unless Scalar::Util::reftype $event eq 'HASH'
    and ref $opts{targets} eq 'ARRAY'; 

  my %extra = defined $opts{options} ? %{ $opts{options} } : ();

  TARGET: while (my $target = shift @{ $opts{targets} }) {
    confess "Expected an IRC::User, IRC::Peer, or IRC::Channel"
      unless blessed $target;

    if        ($target->isa('IRC::Server::Pluggable::IRC::Channel')) {
      ## FIXME Relaying to channel.

      ## FIXME import existing relay bits to method we can dispatch to?
      ##  or dispatch out to a new Channels role managing rules?

      next TARGET
    }

    ## Otherwise we should have a Peer or User.
    if ($target->has_conn) {
      ## Local connect.

      if      ($target->isa('IRC::Server::Pluggable::IRC::User')) {
        ## Local user.
        $self->send_to_routes( 
          $self->__send_parse_identifiers(
            event => $event,
            local => 1,
            %extra,
          ),
          $target->route
        );
      } elsif ($target->isa('IRC::Server::Pluggable::IRC::Peer')) {
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
  ##  Needs IRC::Peer tweak


  my @local_peers = $opts{peers} ? @{ $opts{peers} }
    : $self->peers->list_local_peers;

  my $sent; 
  LPEER: for my $peer (@local_peers) {
    my $route = $peer->route;
    next LPEER if $except_route{$route};

    my $parsed_ev = $self->__send_parse_identifiers(
      peer  => $peer, 
      event => $event,
      ## FIXME needs to use newer iface
      nick_only => $opts{nick_only},
    );
    $self->send_to_routes( $parsed_ev, $route );
    ++$sent
  } # LPEER

  $sent
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

## FIXME
##  Needs to send TS6 prefix & targets appropriately
##  see rb/send.c sendto_one_numeric
##   - needs to take objects, not routes
##       target => $params{target},          ## User
##       prefix => $optional_specified_pfix, ## Convert Peer or $self objs
##       params => [ ],  ## Stays the same
##   - needs to check remote types
##     peers get self name/ID, numeric, target name/ID
##     local gets numeric->to_hash()
##   - consumers should always call send_numeric
##     for automagic TS translation

sub send_numeric {
  my ($self, $numeric, %params) = @_;
  my $target = $params{target};
  confess "Expected a numeric and an IRC::User 'target =>'"
    unless blessed $target
    and $target->isa('IRC::Server::Pluggable::IRC::User');

  if ($target->has_conn) {
    ## Local user. Do prefix conversion.
    my $prefix;
    if (defined $params{prefix}) {
      if (blessed $params{prefix}) {
        $prefix = $params{prefix} == $self ?
          $self->config->server_name : $params{prefix}->name;
      } else {
        $prefix = $params{prefix}
      }
    } else {
      $prefix = $self->config->server_name
    }

    $self->send_to_routes(
      $self->numeric->to_hash(
        target => $target,
        prefix => $prefix,
        params => ( 
          ref $params{params} eq 'ARRAY' ?
            $params{params} : [ $params{params}||() ]
        ),
      ), 
      $target
    );
  } else {
    ## Remote user.
    ## Call ->send_to_targets ?
    ## We want name/SID of self or 'prefix =>' peer
    ## + numeric + target UID or nick
  }
}



=pod

=head2 send_to_routes

B<send_to_routes> / B<send_to_route> are low-level Protocol message
dispatchers; these bridge the Dispatcher layer and are used by the 
higher-level methods detailed above.

=cut

sub send_to_route  { shift->send_to_routes(@_) }
sub send_to_routes {
  my ($self, $output, @ids) = @_;
  unless (ref $output && @ids) {
  confess "send_to_routes() received insufficient params"
    unless @ids;
  $self->dispatcher->to_irc( $output, @ids )
}


1;

=pod

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
