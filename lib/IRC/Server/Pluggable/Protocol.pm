package IRC::Server::Pluggable::Protocol;

## Base class for Protocol sessions.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use POE;

use IRC::Server::Pluggable::Types;


extends 'IRC::Server::Pluggable::Emitter';


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

sub BUILD {
  my ($self) = @_;

  ### FIXME set up object_states etc and $self->_start_emitter()
  $self->set_object_states(
    [
      $self => {
        ## FIXME
      },
      
      (
        $self->has_object_states ? @{ $self->object_states } : ()
      );
    ],
  );

  $self->_start_emitter;
}
### FIXME user / peer / channel tracker objs ?

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

## FIXME need to handle unknown command input



q{
<Gilded> I'm only level 24 myself so I try to avoid the hard quests 
 like "Job" or "Sex"
};


=pod

=cut
