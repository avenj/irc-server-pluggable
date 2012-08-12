package IRC::Server::Pluggable::IRC::Channel;
## Base class for Channels.
## Overridable by Protocols.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable qw/
  Types
  Utils
/;

has 'name' => (
  required => 1,
  is  => 'ro',
  isa => Str,
);

has 'nicknames' => (
  lazy => 1,

  is  => 'ro',
  isa => HashRef[ArrayRef],

  default => sub { {} },
  writer  => 'set_nicknames',
);

has 'modes' => (
  ##  Status modes are handled via nicknames hash and chg_status()
  ##  Relies on ->prefix_map() and ->valid_channel_modes() from Protocol 
  ##  to find out what modes actually are/do, so this all has to be 
  ##  outside of these per-channel objects
  lazy => 1,

  is  => 'ro',
  isa => HashRef,

  default => sub { {} },
  writer  => 'set_modes',
);


has '_list_classes' => (
  ## Map list keys to classes
  lazy => 1,
  
  is  => 'ro',
  isa => HashRef,
  
  default => sub {
    my $base = "IRC::Server::Pluggable::IRC::Channel::List::";

    {
      bans => $base . "Bans",
    },
  },
  
  writer => '_set_list_classes',
);


has 'lists' => (
  ## Ban lists, etc
  lazy => 1,
  
  is  => 'ro',
  isa => HashRef,

  default => sub {
    ## Construct from _list_classes
    my ($self) = @_;

    my $listref = {};

    for my $key (keys %{ $self->_list_classes }) {
      my $class = $self->_list_classes->{$key};
      
      require $class;
      
      $listref->{$key} = $class->new;
    }
    
    $listref
  },
  
  writer => 'set_lists',
);


## IMPORTANT: These functions all currently expect a higher 
##  level layer to handle upper/lower case manipulation.
##  May reconsider this later ...


## User manip
sub add_user {
  my ($self, $nickname, $data) = @_;

  confess "add_user called with no nickname specified"
    unless defined $nickname;

  if (defined $data && ref $data ne 'ARRAY') {
    carp "add_user passed non-ARRAY params argument for $nickname";
    return
  }
  
  $self->nicknames->{$nickname} = $data // []
}

sub del_user {
  my ($self, $nickname) = @_;
  
  delete $self->nicknames->{$nickname}
}

sub users_as_array {
  my ($self) = @_;

  [ keys %{ $self->nicknames } ]
}


## Mode manip

sub chg_status {
  ## ->chg_status( $nickname, $mode_to_add, $excluded_modes )
  ##  (For example, +o excludes +h on some implementations.)
  my ($self, $nickname, $modestr, $exclude) = @_;

  confess "chg_status() called with no nickname specified"
    unless defined $nickname;

  confess "chg_status() called with no mode string specified"
    unless defined $modestr;

  my $final;
  unless ($final = $self->nicknames->{$nickname}) {
    carp 
      "chg_status() called on $nickname but not present on ".$self->name;
    
    return
  }
  
  if (defined $exclude && (my @splitex = split //, $exclude) ) {
    $final = [ grep { !($_ ~~ @splitex) } @$final ]
  }
  
  push @$final, split //, $modestr;

  $self->nicknames->{$nickname} = [ sort @$final ];
}


no warnings 'void';
q{
 <LeoNerd> Hehe.. this does not bode well. I google searched for "MSWin32 
  socket non blocking connect", to read about how to do it. Got 1 404, 1 
  ancient article about 1990s UNIX, one about python, then the 4th 
  result is me, talking about how I don't know how to do it.
};
