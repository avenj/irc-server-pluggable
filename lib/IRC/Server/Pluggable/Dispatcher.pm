package IRC::Server::Pluggable::Dispatcher;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;
use POE;

use IRC::Server::Pluggable qw/
  Constants
  Emitter
  Types
/;


extends 'IRC::Server::Pluggable::Emitter';


has 'backend_opts' => (
  required => 1,
  isa => HashRef,
  is  => 'ro',
  writer => 'set_backend_opts',
);

has '_backend_class' => (
  lazy => 1,
  is   => 'ro',
  isa  => Str,
  writer  => '_set_backend_class',
  default => sub { "IRC::Server::Pluggable::Backend" },
);


has 'backend' => (
  lazy => 1,

  isa => BackendClass,
  is  => 'ro',

  predicate => 'has_backend',
  writer    => 'set_backend',

  default => sub {
    my ($self) = @_;
    
    my $b_class = $self->_backend_class;

    { local $@;
      eval "require $b_class";
      confess "Could not load $b_class : $@" if $@;
    }
    
    $b_class->spawn( %{ $self->backend_opts } )
  },
);


sub BUILD {
  my ($self) = @_;

  $self->set_event_prefix( "backend_ev_" )
    unless $self->has_event_prefix;

  $self->set_object_states(
    [
      $self => {        
        'dispatch' => '_dispatch',
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

  
  $self->_start_emitter;
}

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
  
  $self->_yield( '_emitter_shutdown' );
}


sub ircsock_registered {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  
  my $backend = $_[ARG0];

  $self->set_backend( $backend )
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

  my $cmd = lc($ev->command);

  my $event_name = join '_', $from_type, $cmd ;

  if ($conn->is_peer && $cmd =~ /^[0-9]$/) {
    ## Dispatch _PEER_NUMERIC
    ## FIXME These are probably just being routed to a client wheel.
    ##  Should probably just do that here before we return.
    return
      if $self->process( 'PEER_NUMERIC', $cmd, $conn, $ev ) == EAT_NONE;
    
    $self->emit( 'PEER_NUMERIC', $cmd, $conn, $ev );

    return
  }

  ## process() via our plugin pipeline:
  return 
    if $self->process( $event_name, $conn, $ev ) == EAT_NONE;

  ## .. then emit() to registered sessions:
  $self->emit( $event_name, $conn, $ev );
}

sub ircsock_connector_open {
  ## Opened connection to remote.
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $conn = $_[ARG0];

  my $event_name = 'connected_peer';

  return
    if $self->process( $event_name, $conn ) == EAT_NONE;

  $self->emit( $event_name, $conn )
}

sub ircsock_connector_failure {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## This Connector has had its wheel cleared.
  my $connector = $_[ARG0];
  my ($op, $errno, $errstr) = @_[ARG1 .. ARG3];

  ## FIXME
}

sub ircsock_compressed {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $conn = $_[ARG0];
  ## ircsock is (probably) burstable.

  my $event_name = 'compressed_peer';

  return
    if $self->process( $event_name, $conn ) == EAT_NONE;

  $self->emit( $event_name, $conn );
}

sub ircsock_disconnect {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  ## This $conn has had its wheel cleared.
  my $conn = $_[ARG0];

  ## FIXME figure out type, dispatch accordingly?
}

sub ircsock_listener_created {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $listener = $_[ARG0];

  my $event_name = 'listener_created';
  
  return
    if $self->process( $event_name, $listener ) == EAT_NONE;

  $self->emit( $event_name, $listener );
}

sub ircsock_listener_failure {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $listener = $_[ARG0];

  my ($op, $errno, $errstr) = @_[ARG1 .. ARG3];

  ## FIXME
}

sub ircsock_listener_open {
  ## Accepted connection.
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $conn = $_[ARG0];

  ## FIXME
}

sub ircsock_listener_removed {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $listener = $_[ARG0];

  ## FIXME
}


sub dispatch {
  my $self = shift;

  $self->call( 'dispatch', @_ )
}

sub _dispatch {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## Either a Backend::Event or a hash suitable for POE::Filter::IRCD :	
  my ($out, @ids) = $_[ARG0 .. $#_];

  return
    if $self->process( 'message_dispatch', $out, \@ids ) == EAT_NONE;

  $self->backend->send( $out, @ids )
}


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
