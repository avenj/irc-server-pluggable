package IRC::Server::Pluggable::Dispatcher;
use Defaults::Modern;

use IRC::Server::Pluggable qw/
  Constants
  Types
/;

use POE;

use Module::Runtime 'use_module';

use Moo;
use MooX::late;
use namespace::clean;

with 'MooX::Role::POE::Emitter';


has backend_opts => (
  required  => 1,
  is        => 'ro',
  isa       => HashObj,
  coerce    => 1,
  writer    => 'set_backend_opts',
  predicate => 'has_backend_opts',
  clearer   => 'clear_backend_opts',
);

has _backend_class => (
  lazy    => 1,
  is      => 'ro',
  isa     => Str,
  writer  => '_set_backend_class',
  builder => '_build_backend_class',
);

method _build_backend_class { 'POEx::IRC::Backend' }


has backend => (
  lazy      => 1,
  is        => 'ro',
  isa       => HasMethods[qw/ send session_id /],
  predicate => 'has_backend',
  writer    => 'set_backend',
  builder   => '_build_backend',
);

method _build_backend {
  my $b_class = $self->_backend_class;

  my $obj = use_module($b_class)->spawn( $self->backend_opts->export );
  $self->clear_backend_opts;

  $obj
}


method BUILD {
  $self->set_event_prefix( 'irc_ev_' ) unless $self->has_event_prefix;

  $self->set_object_states(
    [
      $self => +{
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
    +{
      PROCESS => 'D_Proc',
      NOTIFY  => 'D_Notify',
    }
  );

  $self->_start_emitter;
}


## Methods (and backing handlers)

method shutdown (@params) {
  $poe_kernel->post( $self->session_id => shutdown => @params );
  $self
}

sub _shutdown {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $kernel->post( $self->backend->session_id => shutdown => 
    @_[ARG0 .. $#_]
  );

  ## FIXME probably not correct as of Role split
  ## FIXME call an emitter stop directly instead ?
  $self->_yield( '_emitter_shutdown' );
}

method to_irc (@params) {
  $self->call( to_irc => @params )
}

sub _to_irc {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## Either an IRC::Event or a hash suitable for IRC::Filter
  ## + List of either Backend::Connect wheel IDs
  ##   or objs that can give us one
  my ($out, @conns) = @_[ARG0 .. $#_];
  unless (@conns) {
    carp "to_irc() dispatched without any routes! Nothing to do.";
    return
  }

  my %routes;

  TARGET: for my $item (@conns) {
    if (blessed $item) {
      my $id = $item->can('route') ? $item->route
         : $item->can('wheel_id')  ? $item->wheel_id
         : () ;

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

  return if $self->process( to_irc => $out, \@route_ids ) == EAT_ALL;

  $self->backend->send( $out, @route_ids )
}


## ircsock_* handlers

sub ircsock_compressed {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $conn = $_[ARG0];
  ## Link is probably burstable
  $self->emit( peer_compressed => $conn );
}

sub ircsock_connector_failure {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## This Connector has had its wheel cleared.
#  my $connector = $_[ARG0];
#  my ($op, $errno, $errstr) = @_[ARG1 .. ARG3];

  ## Not much a plugin can do here, particularly ...
  ## emit() only:
  $self->emit( connector_failure => @_[ARG0 .. ARG3] )
}

sub ircsock_connector_open {
  ## Opened connection to remote.
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $conn = $_[ARG0];
  $self->emit( peer_connected => $conn );
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

  $self->emit( $event_name => $conn )
}

sub ircsock_connection_idle {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  $self->emit( connection_idle => @_[ARG0 .. $#_] );
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

    $self->emit( peer_numeric => $conn, $ev );

    return
  }

  my $cmd = lc($ev->command);

  ## _client_cmd
  ## _peer_cmd
  ## _unknown_cmd
  my $event_name = join '_', $from_type, 'cmd' ;

  $self->emit( $event_name => $conn, $ev );
}

sub ircsock_listener_created {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $listener = $_[ARG0];
  $self->emit( listener_created => $listener );
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

  $self->emit( listener_failure =>
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
  $self->emit( listener_accepted => $conn );
}

sub ircsock_listener_removed {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  ## This listener is no longer active (wheel is cleared)
  $self->emit( listener_removed => $_[ARG0] )
}

sub ircsock_registered {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  $self->set_backend( $_[ARG0] )
}


no warnings 'void';
print q{
 <nitric> the more you think about facebook actions in real life, the
  weirder facebook seems
 <nitric> irl, I DON'T want people writing on my wall at 1am
 <nitric> or poking me
 <Schroedingers_hat> HEY YOU HELP ME WITH MY GARDEN!
 <Schroedingers_hat> Who are you?
 <Schroedingers_hat> GIVE ME SOME CARROTS
} unless caller;


=pod

=cut
