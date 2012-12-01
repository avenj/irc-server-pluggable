package IRC::Server::Pluggable::Dispatcher;

## FIXME
##  Hum.
##  All of this should be torn out and moved into
##  either Backend (to_irc bits) or a Protocol::Role
##  (ircsock_* handlers)

use 5.12.1;
use strictures 1;

use Carp;
use Moo;
use POE;

use IRC::Server::Pluggable qw/
  Constants
  Types
/;

use namespace::clean -except => 'meta';


with 'MooX::Role::POE::Emitter';


has 'backend_opts' => (
  required  => 1,
  is        => 'ro',
  isa       => HashRef,
  writer    => 'set_backend_opts',
  predicate => 'has_backend_opts',
  clearer   => 'clear_backend_opts',
);

has '_backend_class' => (
  lazy    => 1,
  is      => 'ro',
  isa     => Str,
  writer  => '_set_backend_class',
  builder => '_build_backend_class',
);

sub _build_backend_class { "IRC::Server::Pluggable::Backend" }


has 'backend' => (
  lazy      => 1,
  is        => 'ro',
  isa       => HasMethods[qw/ send session_id /],
  predicate => 'has_backend',
  writer    => 'set_backend',
  builder   => '_build_backend',
);

sub _build_backend {
  my ($self) = @_;

  my $b_class = $self->_backend_class;

  { local $@;
      eval "require $b_class";
      confess "Could not load $b_class : $@" if $@;
  }

  my $obj = $b_class->spawn( %{ $self->backend_opts } );
  $self->clear_backend_opts;

  $obj
}


sub BUILD {
  my ($self) = @_;

  $self->set_event_prefix( "irc_ev_" )
    unless $self->has_event_prefix;

  $self->set_object_states(
    [
      $self => {
        'to_irc'   => '_to_irc',
        'shutdown' => '_shutdown',
      },

      $self => [
        'ircsock_registered',

        'ircsock_connection_idle',

        'ircsock_input',

        'ircsock_connector_open',
        'ircsock_connector_failure',

        'ircsock_disconnect',

        'ircsock_compressed',

        'ircsock_listener_created',
        'ircsock_listener_failure',
        'ircsock_listener_open',
        'ircsock_listener_removed',
      ],

      ( $self->has_object_states ? @{$self->object_states} : () ),
    ],
  );

  $self->set_pluggable_type_prefixes(
    {
      PROCESS => 'D_Proc',
      NOTIFY  => 'D_Notify',
    }
  );

  $self->_start_emitter;
}


## Methods (and backing handlers)

sub shutdown {
  my $self = shift;

  $poe_kernel->post( $self->session_id,
    'shutdown',
    @_
  );

  1
}

sub _shutdown {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $kernel->post( $self->backend->session_id,
    'shutdown',
    @_[ARG0 .. $#_]
  );

  ## FIXME probably not correct as of Role split
  ## FIXME call an emitter stop directly instead ?
  $self->_yield( '_emitter_shutdown' );
}

sub to_irc {
  my $self = shift;

  $self->yield( 'to_irc', @_ )
}

sub to_irc_now {
  my $self = shift;

  $self->call( 'to_irc', @_ )
}

sub _to_irc {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## Either an IRC::Event or a hash suitable for IRC::Filter
  ## + List of either Backend::Connect wheel IDs
  ##   or objs that can give us one
  my ($out, @conns) = @_[ARG0 .. $#_];
  return unless @conns;

  my %routes;

  TARGET: for my $item (@conns) {
    if ( is_Object($item) ) {
      my $id = $item->can('route') ? $item->route
         : $item->can('wheel_id')  ? $item->wheel_id : undef ;
      unless (defined $id) {
        carp "Unknown target type $item, ID undefined";
        next TARGET
      }
      $routes{$id}++
    } else {
      $routes{$item}++
    }
  }

  my @route_ids = keys %routes;

  return if $self->process( 'to_irc', $out, \@route_ids ) == EAT_ALL;

  $self->backend->send( $out, @route_ids )
}


## ircsock_* handlers

sub ircsock_compressed {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $conn = $_[ARG0];

  ## Link is probably burstable

  my $event_name = 'peer_compressed';

  $self->emit( $event_name, $conn );
}

sub ircsock_connector_failure {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## This Connector has had its wheel cleared.
#  my $connector = $_[ARG0];
#  my ($op, $errno, $errstr) = @_[ARG1 .. ARG3];

  ## Not much a plugin can do here, particularly ...
  ## emit() only:
  $self->emit( 'connector_failure', @_[ARG0 .. ARG3] )
}

sub ircsock_connector_open {
  ## Opened connection to remote.
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $conn = $_[ARG0];

  my $event_name = 'peer_connected';

  $self->emit( $event_name, $conn );
}

sub ircsock_disconnect {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  ## This $conn has had its wheel cleared.
  my $conn = $_[ARG0];

  my $event_name;
  if ($conn->is_peer) {
    $event_name = 'peer_disconnected'
  } elsif ($conn->is_client) {
    $event_name = 'client_disconnected'
  } else {
    $event_name = 'unknown_disconnected'
  }

  $self->emit( $event_name, $conn )
}

sub ircsock_connection_idle {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $self->emit( 'connection_idle', @_[ARG0 .. $#_] );
}

sub ircsock_input {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $ev)     = @_[ARG0, ARG1];

  my $from_type =
    $conn->is_peer   ? 'peer'   :
    $conn->is_client ? 'client' :
                       'unknown';

  if ($conn->is_peer && $ev->command =~ /^[0-9]+$/) {
    ## Numerics from peers being routed somewhere.

    ## P_peer_numeric
    ## irc_ev_peer_numeric / N_peer_numeric

    $self->emit( 'peer_numeric', $conn, $ev );

    return
  }

  my $cmd = lc($ev->command);

  ## _client_cmd
  ## _peer_cmd
  ## _unknown_cmd
  my $event_name = join '_', $from_type, 'cmd' ;

  $self->emit( $event_name, $conn, $ev );
}

sub ircsock_listener_created {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $listener = $_[ARG0];

  my $event_name = 'listener_created';

  $self->emit( $event_name, $listener );
}

sub ircsock_listener_failure {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  my $listener = $_[ARG0];
  my ($op, $errno, $errstr) = @_[ARG1 .. ARG3];

  ## FIXME
  ## Could not listen on a particular port.
  ## This should at least be logged...
  ## Possibly announced to IRC on a rehash, f.ex.
  ## ... haven't quite worked out logging yet.
  my $event_name = 'listener_failure';

  $self->emit( $event_name,
    $listener,
    $op,
    $errno,
    $errstr
  )
}

sub ircsock_listener_open {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $conn = $_[ARG0];

  ## Accepted connection.

  my $event_name = 'listener_accepted';

  $self->emit( $event_name, $conn );
}

sub ircsock_listener_removed {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## This listener is no longer active (wheel is cleared)
  my $listener = $_[ARG0];

  $self->emit( 'listener_removed', $listener )
}

sub ircsock_registered {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  my $backend = $_[ARG0];

  $self->set_backend( $backend )
}


no warnings 'void';
q{
 <nitric> the more you think about facebook actions in real life, the
  weirder facebook seems
 <nitric> irl, I DON'T want people writing on my wall at 1am
 <nitric> or poking me
 <Schroedingers_hat> HEY YOU HELP ME WITH MY GARDEN!
 <Schroedingers_hat> Who are you?
 <Schroedingers_hat> GIVE ME SOME CARROTS
};


=pod

=cut
