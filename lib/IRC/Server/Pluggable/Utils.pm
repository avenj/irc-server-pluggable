package IRC::Server::Pluggable::Utils;

use 5.12.1;
use strictures 1;
use Carp;

use IRC::Utils qw/matches_mask normalize_mask/;

use base 'Exporter';
our %EXPORT_TAGS = (

  network => [ qw/  

    get_unpacked_addr

  / ],

  irc  => [ qw/
    matches_mask
    normalize_mask

    lc_irc
    uc_irc

    parse_user

  / ],
);

our @EXPORT;
{
  my %s;
  push @EXPORT,
    grep { !$s{$_}++ } @{ $EXPORT_TAGS{$_} } for keys %EXPORT_TAGS;
}

sub import {
  __PACKAGE__->export_to_level(1, @_)
}


## Networking-related
use Socket qw/
  :addrinfo

  sockaddr_family

  AF_INET
  inet_ntoa
  unpack_sockaddr_in

  AF_INET6
  inet_ntop
  unpack_sockaddr_in6
/;

sub get_unpacked_addr {
  ## v4/v6-compat address unpack.
  my ($sock_packed) = @_;

  ## TODO getnameinfo instead?
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
      $sockaddr   = inet_ntoa($sockaddr);
      $inet_proto = 4;

      last FAMILY
    }

    confess "Unknown socket family type"
  }

  ($inet_proto, $sockaddr, $sockport)
}


## IRC-related
sub lc_irc ($;$) {
  my ($string, $casemap) = @_;
  
  $casemap = lc( $casemap // 'rfc1459' );

  for ($casemap) {
    $string =~ tr/A-Z[]\\/a-z{}|/  when "strict-rfc1459";
    $string =~ tr/A-Z/a-z/         when "ascii";
    default { $string =~ tr/A-Z[]\\~/a-z{}|^/ }
  }

  $string
}

sub uc_irc ($;$) {
  my ($string, $casemap) = @_;
  
  $casemap = lc( $casemap // 'rfc1459' );
  
  for ($casemap) {
    $string =~ tr/a-z{}|/A-Z[]\\/  when "strict-rfc1459";
    $string =~ tr/a-z/A-Z/         when "ascii";
    default { $string =~ tr/a-z{}|^/A-Z[]\\~/ }
  }
  
  $string
}

sub parse_user ($) {
  my ($full) = @_;
  
  confess "parse_user() called with no arguments"
    unless defined $full;

  my ($nick, $user, $host) = split /[!@]/, $full;

  wantarray ? ($nick, $user, $host) : $nick
}


1;

=pod

=head1 NAME

IRC::Server::Pluggable::Utils - IRC::Server::Pluggable tools

=head1 SYNOPSIS

  use IRC::Server::Pluggable::Utils;
  
=head1 DESCRIPTION

Various small utilities for L<IRC::Server::Pluggable>.

=head2 IRC-related

=head3 lc_irc

  my $lower = lc_irc( $string [, $casemap ] );

Takes a string and an optional casemap:

  'ascii'           a-z      -->  A-Z
  'rfc1459'         a-z{}|^  -->  A-Z[]\~   (default)
  'strict-rfc1459'  a-z{}|   -->  A-Z[]\

Returns the string (lowercased according to the specified rules).

=head3 uc_irc

  my $upper = uc_irc( $string [, $casemap ] );

The reverse of L</lc_irc>.

=head3 parse_user

  my ($nick, $user, $host) = parse_user( $full );

Split a 'nick!user@host' into components.

Returns just the nickname in scalar context.

=head2 Network-related

=head3 get_unpacked_addr

  my ($inet_proto, $sock_addr, $sock_port) = get_unpacked_addr( 
    getsockname($sock)
  );

Given a packed socket address, returns an Internet protocol version (4 or 
6) and the unpacked address and port (as a list, see example above).


=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
