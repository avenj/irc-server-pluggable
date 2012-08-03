package IRC::Server::Pluggable::Emitter;
our $VERSION;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use Object::Pluggable::Constants qw/:ALL/;

extends 'Object::Pluggable';


has 'alias' => (
  ## Optionally instantiate with a kernel alias:
  lazy => 1,
  is   => 'ro',
  isa  => Str,
  predicate => 'has_alias',
);

has 'session_id' => (
  lazy => 1,
  is   => 'ro',
  isa  => Defined,  
  predicate => 'has_session_id',
  writer    => 'set_session_id',
);


sub import {
  my $self = shift;
  
  my $pkg = caller();
  
  {
    no strict 'refs';
    for (qw/ EAT_NONE EAT_CLIENT EAT_PLUGIN EAT_ALL /) {
      *{ $pkg .'::' .$_ } 
        = *{ 'Object::Pluggable::Constants::PLUGIN_' .$_ }
    }
  }    
}

sub _spawn_emitter {
  ## Call me from subclass to set up our Emitter.
  my ($self, %args) = @_;
  $args{lc $_} = delete $args{$_} for keys %args;

  ## FIXME
  ##  process args
  ##  call _pluggable_init
  ##  spawn Session
  $self->_pluggable_init(
  
  );
  
  POE::Session->create(
  
  );
  
  
}


## From our super:
around '_pluggable_event' => sub {
  my ($orig, $self) = splice @_, 0, 2;


};


## Our Session's handlers:
sub _start {
  my ($kernel, $self, $session) = @_[KERNEL, OBJECT, SESSION];
  
  $self->set_session_id( $session->ID );

  if ( $self->has_alias ) {
    ## Set alias
  } else {
    ## Incr refcount
  }
}

sub shutdown {
  ## FIXME call _pluggable_destroy
  
}


q{
 <tberman> who wnats to sing a song with me?
 <tberman> its the i hate php song
 * rac adds a stanza to tberman's song about braindead variable scoping
   that just made forums search return a bunch of false positives when 
   you search for posts by poster and return by topics  
};


=pod


=cut
