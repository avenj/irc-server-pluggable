package IRC::Server::Pluggable::Protocol;

## Base class for Protocol sessions.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use POE;

use IRC::Server::Pluggable::Types;

extends 'POE::Component::Syndicator';


### IRCD-relevant attribs
has 'casemapping' => (
  lazy => 1,

  is  => 'rw',
  isa => CaseMap,
  
  default => sub { 'rfc1459' },
);

has 'max_chan_length' => (
  lazy => 1,
  
  is  => 'rw',
  isa => Int,
  
  default => sub { 30 },
);

has 'max_nick_length' => (
  lazy => 1,
  
  is  => 'rw',
  isa => Int,
  
  default => sub { 9 },
);

has 'max_msg_targets' => (
  lazy => 1,
  
  is  => 'rw',
  isa => Int,
  
  default => sub { 4 },
);

has 'network_name' => (
  lazy => 1,
  
  is  => 'rw',
  isa => Str,
  
  default => sub { 'NoNetworkDefined' },
);

has 'prefix_map' => (
  ## Map PREFIX= to channel mode characters.
  ## (These also compose the valid status mode list)
  lazy => 1,

  isa => HashRef,
  is  => 'rw',

  default => sub {
    {
      '@' => 'o',
      '+' => 'v',
    },
  },  
);

has 'valid_channel_modes' => (
  lazy => 1,
  
  isa => HashRef,
  is  => 'rw',
  
  default => sub {
    ## ISUPPORT CHANMODES=1,2,3,4
    ## Channel modes fit in four categories:
    ##  'LIST'     -> Modes that manipulate list values
    ##  'PARAM'    -> Modes that require a parameter
    ##  'SETPARAM' -> Modes that only require a param when set
    ##  'SINGLE'   -> Modes that take no parameters
    {
      LIST     => [ 'b' ],
      PARAM    => [ 'k' ],
      SETPARAM => [ 'l' ],
      SINGLE   => [ split '', 'imnpst' ],
    },
  },
);

has 'valid_user_modes' => (
  lazy => 1,
  
  isa => ArrayRef,
  is  => 'rw',
  
  default => sub {
    [ split '', 'iaow' ]
  },
);

has 'version_string' => (
  lazy => 1,
  
  isa => Str,
  is  => 'rw',
  
  default => sub { ref $self },
);


### FIXME user / peer / channel tracker objs ?

### Session-related.
has 'session_id' => (
  lazy => 1,
  
  is  => 'ro',
  isa => Defined,
  
  writer    => 'set_session_id',
  predicate => 'has_session_id',
);

has 'object_states' => (
  is  => 'ro',
  isa => sub {
    is_ArrayRef($_[0]) or is_HashRef($_[0])
      or die "$_[0] is not an ArrayRef or HashRef"
  },
  
  default => sub {
    [
      '_start',
      '_stop',

      'ircsock_listener_open',

      'ircsock_connector_failure',
      'ircsock_connector_open',
      
      'ircsock_connection_idle',
      
      'irc_cmd_ping',
      
    ],
  },
);


sub spawn {
  my ($class, %args) = @_;
  
  $args{lc $_} = delete $args{$_} for keys %args;
  
  my $self = ref($class) ? $class : $class->new(%args);

  ## FIXME
  ## spawn session
  ## spawn syndicator

  my $sess_id = POE::Session->create(
    object_states => [
      $self => $self->object_states,
    ],
  )->ID;
  
  $self->set_session_id( $sess_id );

  $self
}

sub _start { }

sub _stop { }

### FIXME something clever to plugin-process events
##        before handling?
## 
##  -> receive relayed ircsock_* event notification
##     (except _input)
##  -> receive dispatched irc_cmd_* events
##    -> call plugin processor method
##       args: obj ?
##    -> syndicate synchronous event
##       args: obj ?
##    -> dispatch output back to Dispatcher

## FIXME need an overridable way to format numeric replies

sub _dispatch {
  my ($self, $event, @args) = @_;
  
  my $eat = $self->send_user_event(
    $event,
    \@args
  );
  
  return if $eat == PLUGIN_EAT_ALL;

  ## FIXME
}

### Received via post() from Dispatcher:

sub irc_unknown_cmd {
  ## FIXME Dispatcher should call this if no other method found
}

sub irc_cmd_ping {
  my ($self, $conn, @params) = @_;  
  
}


q{
<Gilded> I'm only level 24 myself so I try to avoid the hard quests 
 like "Job" or "Sex"
};


=pod

=cut
