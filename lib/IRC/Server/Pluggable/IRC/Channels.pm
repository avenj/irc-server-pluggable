package IRC::Server::Pluggable::IRC::Channels;

## Maintain a collection of Channel objects.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable qw/
  Types
  Utils
/;


has 'casemap' => (
  required => 1,
  is  => 'ro',
  isa => CaseMap,
);

with 'IRC::Server::Pluggable::Role::CaseMap';



has '_channels' => (
  ## Map (lowercased) channel names to Channel objects.
  lazy => 1,
  
  is  => 'ro',
  isa => HashRef,
  
  default => sub { {} },
);


sub as_array {
  my ($self) = @_;

  [ map { $self->_channels->{$_}->name } keys %{ $self->_channels } ]
}


sub by_name {
  my ($self, $name) = @_;
  
  unless (defined $name) {
    carp "by_name() called with no name specified";
    return
  }
  
  $self->_channels->{ $self->lower($name) }
}

sub add {
  my ($self, $chan) = @_;
  
  confess "$chan is not a IRC::Server::Pluggable::IRC::Channel"
    unless is_Object($chan)
    and $chan->isa('IRC::Server::Pluggable::IRC::Channel');

  my $name = $self->lower( $chan->name );

  $self->_channels->{$name} = $chan;

  $chan
}

sub del {
  my ($self, $name) = @_;

  confess "del() called with no channel specified"
    unless defined $name;

  $name = $self->lower($name);
  
  delete $self->_channels->{$name}
}


q{
 <Capn_Refsmmat> Gilded: Have you considered employment as a cheap 
   punster?   
  <Gilded> Pun good - make many pun is good for brain, also 
   then make better English in future times
  <Gilded> I also take slight offense at "cheap" considering all my puns 
   are solid gold
};


=pod

=cut
