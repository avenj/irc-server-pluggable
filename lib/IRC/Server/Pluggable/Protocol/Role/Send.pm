package IRC::Server::Pluggable::Protocol::Role::Send;

use 5.12.1;
use Carp;
use Moo::Role;
use strictures 1;

requires qw/
  config

  dispatcher

  numeric
/;


sub send_to_route {
  my ($self, $output, $id) = @_;
  unless (ref $output && defined $id) {
    carp "send_to_route() received insufficient params"
    return
  }

  $self->dispatcher->dispatch( $output, $id )
}

sub send_to_routes {
  my ($self, $output, @ids) = @_;
  unless (ref $output && @ids) {
    carp "send_to_routes() received insufficient params"
    return
  }

  $self->dispatcher->dispatch( $output, @ids )
}


## FIXME

1;
