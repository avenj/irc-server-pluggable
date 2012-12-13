package IRC::Server::Pluggable::Protocol::Role::Stats;

use Moo::Role;
use strictures 1;

use namespace::clean;


with 'IRC::Server::Pluggable::Role::Interface::IRCd';
requires qw/
  dispatch
/;


sub cmd_from_client_stats {
  my ($self, $conn, $event, $user) = @_;

  unless (@{ $event->params }) {
    ## FIXME bad args
    return
  }

  my $char = substr $event->params->[0], 0, 1;
  my $meth = 'r_stats_report_'.$char;
  if ( $self->can($meth) ) {
    my $eventset = $self->$meth($conn, $event, $user);
    ## FIXME send eventset
  } else {
    ## FIXME unknown stats char
  }
}

sub cmd_from_peer_stats {
  ## FIXME
}


sub r_stats_report_u {
  my ($self) = @_;

  my $delta = time - $^T;
  ## FIXME
}

sub r_stats_report_m {
  ## FIXME report usage counts for valid cmds -- do we care?
}


1;
