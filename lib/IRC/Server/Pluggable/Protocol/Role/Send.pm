package IRC::Server::Pluggable::Protocol::Role::Send;

use 5.12.1;
use Carp;
use Moo::Role;
use strictures 1;

use namespace::clean -except => 'meta';


requires qw/
  config

  dispatcher

  numeric
/;

### FIXME should sendq management live here... ?

### FIXME truncate outgoing strings to 510 chars?
### ->send_to_route( $ref, $id )
### ->send_to_routes( $ref, @ids )
###    These take either a Backend::Event or a POE::Filter::IRCD hash.
###    Check args and bridge dispatcher.

sub send_to_route {
  my ($self, $output, $id) = @_;
  unless (ref $output && defined $id) {
    carp "send_to_route() received insufficient params";
    return
  }

  $self->dispatcher->dispatch( $output, $id )
}

sub send_to_routes {
  my ($self, $output, @ids) = @_;
  unless (ref $output && @ids) {
    carp "send_to_routes() received insufficient params";
    return
  }

  $self->dispatcher->dispatch( $output, @ids )
}

## FIXME
##  methods for:

##   - send to remote channel
##   - send to channel except for origin
##   - send to users on local server who share channel with user

##   - send to users with certain modes on a channel?

##   - send to mask-matched peers?

##   - send to users with specified flags or modes?

## message relay logic?

1;
