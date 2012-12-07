package IRC::Server::Pluggable::Backend::Utils;

use 5.12.1;
use strictures 1;
use Carp;


use base 'Exporter';


our @EXPORT = qw/
  get_unpacked_addr
/;

  
use Socket qw/
  :addrinfo

  sockaddr_family

  AF_INET
  unpack_sockaddr_in

  AF_INET6
  inet_ntop
  unpack_sockaddr_in6
/;


sub get_unpacked_addr {
  ## v4/v6-compat address unpack.
  my ($sock_packed) = @_;

  confess "No address passed to get_unpacked_addr"
    unless $sock_packed;

  my $sock_family = sockaddr_family($sock_packed);

  my ($inet_proto, $sockaddr, $sockport);

  FAMILY: {

    if ($sock_family == AF_INET6) {
      ($sockport, $sockaddr) = unpack_sockaddr_in6($sock_packed);
      $sockaddr   = inet_ntop(AF_INET6, $sockaddr);
      $inet_proto = 6;

      last FAMILY
    }

    if ($sock_family == AF_INET) {
      ($sockport, $sockaddr) = unpack_sockaddr_in($sock_packed);
      $sockaddr   = inet_ntop(AF_INET, $sockaddr);
      $inet_proto = 4;

      last FAMILY
    }

    confess "Unknown socket family type"
  }

  ($inet_proto, $sockaddr, $sockport)
}



1;

=pod

=head1 NAME

IRC::Server::Pluggable::Backend::Utils

=head1 SYNOPSIS

  use IRC::Server::Pluggable::Backend::Utils;

=head1 DESCRIPTION

Backend utilities for L<IRC::Server::Pluggable>.

=head2 Functions

=head3 get_unpacked_addr

  my ($inet_proto, $sock_addr, $sock_port) = get_unpacked_addr( 
    getsockname($sock)
  );

Given a packed socket address, returns an Internet protocol version (4 or 
6) and the unpacked address and port (as a list, see example above).

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
