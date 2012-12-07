package IRC::Server::Pluggable::IRC::EventSet;

use Carp;
use strictures 1;

use Scalar::Util  'blessed';
use Storable      'dclone';

use IRC::Server::Pluggable::IRC::Event;

use namespace::clean;

sub new {
  my ($class, @events) = @_;
  my $self = [];
  bless $self, $class;

  if (@events) {
    $self->push(@events)
  }

  $self
}

sub _valid_ev {
  my ($self, $event) = @_;

  EVENT: {
    if (blessed $event
      && $event->isa('IRC::Server::Pluggable::IRC::Event') ) {
      last EVENT
    }

    if (ref $event eq 'HASH') {
      $event = IRC::Server::Pluggable::IRC::Event->new(%$event);
      last EVENT
    }

    confess "Expected IRC::Event or compatible HASH, got $event"
  }  ## EVENT

  $event
}

sub add { shift->push(@_) }

sub by_index {
  my ($self, $idx) = @_;

  confess "by_index() expects an array index"
    unless defined $idx;

  $self->[$idx]
}

sub set_index {
  my ($self, $idx, $event) = @_;
  $self->[$idx] = $self->_valid_ev($event)
}

sub has_events {
  my ($self) = @_;
  @$self
}

sub list {
  my ($self) = @_;
  wantarray ? @$self : [ @$self ]
}

sub pop {
  my ($self) = @_;
  pop @$self
}

sub push {
  my ($self, @events) = @_;
  push @$self, map { $self->_valid_ev($_) } @events
}

sub shift {
  my ($self) = @_;
  shift @$self
}

sub unshift {
  my ($self, @events) = @_;
  unshift @$self, map { $self->_valid_ev($_) } @events
}

sub clone {
  my ($self) = @_;
  my @events = map {; 
    blessed($_)->new(%$_)
  } @$self;
  blessed($self)->new( @events );
}

sub consume {
  my ($self, $evset) = @_;
  confess "Expected an IRC::Server::Pluggable::IRC::EventSet"
    unless blessed $evset
    and $evset->isa('IRC::Server::Pluggable::IRC::EventSet');

  while (my $ev = $evset->shift) {
    $self->push($ev)
  }

  $self
}

sub combine {
  my ($self, $evset) = @_;
  confess "Expected an IRC::Server::Pluggable::IRC::EventSet"
    unless blessed $evset
    and $evset->isa('IRC::Server::Pluggable::IRC::EventSet');

  $self->push($_) for $evset->list;

  $self
}

sub new_event {
  my $self = CORE::shift;
  IRC::Server::Pluggable::IRC::Event->new(@_)
}

1;

=head1 NAME

IRC::Server::Pluggable::IRC::EventSet - Accumulate IRC::Events

=head1 SYNOPSIS

  my $evset = IRC::Server::Pluggable::IRC::EventSet->new(
    {
      prefix => $prefix,
      target => $target,
      params => [ @params ],
    },

  #    . . .

  );

  $evset->unshift( @prepend_events );

  $evset->push( @more_events );

  while (my $event = $evset->shift) {
    my $prefix = $event->prefix;
    #    . . .
  }

  my $last = $evset->pop;

  my $second = $evset->by_index(1);

=head1 DESCRIPTION

An ARRAY-type object that takes (and validates) either
L<IRC::Server::Pluggable::IRC::Event> object instances or a HASH that
will be fed to L<IRC::Server::Pluggable::IRC::Event> ->new().


FIXME


=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>
