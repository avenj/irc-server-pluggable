package IRC::Server::Pluggable::Backend::EventSet;

use Carp;
use strictures 1;

use Scalar::Util  'blessed';
use Storable      'dclone';

use IRC::Server::Pluggable::Backend::Event;

use namespace::clean -except => 'meta';

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
      && $event->isa('IRC::Server::Pluggable::Backend::Event') ) {
      last EVENT
    }

    if (ref $event eq 'HASH') {
      $event = IRC::Server::Pluggable::Backend::Event->new(%$event);
      last EVENT
    }

    confess "Expected Backend::Event or compatible HASH, got $event"
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

sub clone {
  my ($self) = @_;
  dclone($self)
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

1;

=head1 NAME

IRC::Server::Pluggable::Backend::EventSet - Accumulate Backend::Events

=head1 SYNOPSIS

  my $evset = IRC::Server::Pluggable::Backend::EventSet->new(
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
L<IRC::Server::Pluggable::Backend::Event> object instances or a HASH that
will be fed to L<IRC::Server::Pluggable::Backend::Event> ->new().


FIXME


=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>
