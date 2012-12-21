package IRC::Server::Pluggable::Client::Lite;

use 5.12.1;
use Moo;
use POE;


use MooX::Struct -rw,
  State => [ qw/
    channels
    nick_name
    server_name
  / ],

  Channel => [ qw/
    nicknames
    topic
    modes
  / ],
;

use IRC::Server::Pluggable qw/
  Backend
  Types
/;

with 'MooX::Role::POE::Emitter';


has backend => (
  lazy    => 1,
  is      => 'ro',
  isa     => InstanceOf['IRC::Server::Pluggable::Backend'],
  builder => '_build_backend',
);

has connector_id => (
  lazy      => 1,
  is        => 'ro',
  isa       => Defined,
  writer    => '_set_connector_id',
  predicate => '_has_connector_id',
  default   => sub { -1 },
);

has state => (
  lazy    => 1,
  is      => 'ro',
  isa     => Object,
  default => sub { 
    State[
      channels    => [],
      nick_name   => '',
      server_name => '',
    ]
  },
);

sub _build_backend {
  my ($self) = @_;
  ## FIXME create a Backend with a non-colonifying filter?
}

sub BUILD {
  my ($self) = @_;

  $self->set_object_states(
    [
      $self => [ qw/
        ircsock_input
        ircsock_connector_open
        ircsock_connector_failure
      / ],
      $self => {
        connect_to  => '_connect_to',
        disconnect  => '_disconnect',
        send        => '_send',
        privmsg     => '_privmsg',
        notice      => '_notice',
        mode        => '_mode',
        join        => '_join',
        part        => '_part',
      },
      (
        $self->has_object_states ? @{ $self->object_states } : ()
      ),
    ],
  );

  $self->set_event_prefix('irc_client_')
    unless $self->has_event_prefix;
  
  $self->_start_emitter;
}

sub _emitter_started {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  $kernel->post( $self->backend->session_id, 'register' );
}

sub stop {
  my ($self) = @_;
  $poe_kernel->post( $self->backend->session_id, 'shutdown' );
  $self->_shutdown_emitter;
}

### ircsock_*

sub ircsock_connector_open {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $conn = $_[ARG0];
  ## FIXME Try to register with remote, issue events
}

sub ircsock_connector_failure {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $connector = $_[ARG0];
  my ($op, $errno, $errstr) = @_[ARG1 .. ARG3];
  ## FIXME
}

sub ircsock_input {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  ## FIXME dispatch/emit
}

### FIXME figure out what we ought do wrt processing incoming dispatchable
## events


### Public

sub connect_to {
  ## Tell Backend to open a Connector
}

sub _connect_to {
  my ($kern, $self) = @_[KERNEL, OBJECT];

}

sub disconnect {

}

sub _disconnect {

}

sub send {
  ## Send a line, hash, or Event
}

sub _send {

}

## Sugar, and POE-dispatchable counterparts.
sub notice {

}

sub _notice {

}

sub privmsg {

}

sub _privmsg {

}

sub mode {

}

sub _mode {

}

sub join {

}

sub _join {

}

sub part {

}

sub _part {

}

## FIXME
##  Hammer out a reasonably common interface between
##   a Client::Lite and Client::Pseudo
##   (shove interface into a Role::Interface::Client)

1;
