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


sub add {
  my ($self, $chan) = @_;

  confess "$chan is not a IRC::Server::Pluggable::IRC::Channel"
    unless is_Object($chan)
    and $chan->isa('IRC::Server::Pluggable::IRC::Channel');

  $self->_channels->{ $self->lower($chan->name) } = $chan;

  $chan
}

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

sub del {
  my ($self, $name) = @_;

  confess "del() called with no channel specified"
    unless defined $name;

  delete $self->_channels->{ $self->lower($name) }
}

1;

=pod

=cut
