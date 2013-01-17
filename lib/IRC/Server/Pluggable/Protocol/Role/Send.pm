package IRC::Server::Pluggable::Protocol::Role::Send;

use 5.12.1;
use Carp;
use Moo::Role;
use strictures 1;

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
  if ( is_Object($peer_name_or_obj) ) {
    ## Peer obj.
    return $peer_name_or_obj->route
  }
  ## Name or route ID, we hope.
  return $self->peers->by_name($peer_name_or_obj) || $peer_name_or_obj    
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

  my $as_hash = %$event;
  my $sent; 
  LPEER: for my $peer ($self->peers->list_local_peers) {
    my $route = $peer->route;
    next LPEER if $except_route{$route};

    for ($opts{from} // '') {
      ## Use SID or name as-needed.
      when ('localserver') {
        $as_hash->{prefix} = $self->__send_peer_correct_self_prefix($peer)
      }
      when ('localuser') {
        ## FIXME similar to localserver but we need a User obj
        ## & get prefix based on remote peer type
        ## FIXME add localuser_nickonly ?
      }
    }

    ## Automagically id_or_nick() any User obj in params
    $as_hash->{params} = [
      map {;
        my $param = $_;
        $param = $self->id_or_nick($param, $peer)
          if is_Object($param)
          and $param->isa('IRC::Server::Pluggable::IRC::User');
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


sub send_to_route  { shift->send_to_routes(@_) }
sub send_to_routes {
  my ($self, $output, @ids) = @_;
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
