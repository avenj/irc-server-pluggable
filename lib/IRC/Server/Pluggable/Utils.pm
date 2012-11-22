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

    mode_to_hash

  / ],
);

$EXPORT_TAGS{all} = [ map { @$_ } values %EXPORT_TAGS ];

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

  unless (wantarray) {
    Carp::cluck(
      "Possibly mistaken use of get_unpacked_addr, caller does not want list"
    );
  }

  ($inet_proto, $sockaddr, $sockport)
}


## IRC-related

# lc_ / uc_irc are prototyped to vaguely line up with lc / uc
sub lc_irc ($;$) {
  my ($string, $casemap) = @_;
  $casemap = lc( $casemap // 'rfc1459' );

  CASE: {
    if ($casemap eq 'strict-rfc1459') {
      $string =~ tr/A-Z[]\\/a-z{}|/;
      last CASE
    }

    if ($casemap eq 'ascii') {
      $string =~ tr/A-Z/a-z/;
      last CASE
    }

    $string =~ tr/A-Z[]\\~/a-z{}|^/
  }

  $string
}

sub uc_irc ($;$) {
  my ($string, $casemap) = @_;
  $casemap = lc( $casemap // 'rfc1459' );

  CASE: {
    if ($casemap eq 'strict-rfc1459') {
      $string =~ tr/a-z{}|/A-Z[]\\/;
      last CASE
    }

    if ($casemap eq 'ascii') {
      $string =~ tr/a-z/A-Z/;
      last CASE
    }

    $string =~ tr/a-z{}|^/A-Z[]\\~/
  }

  $string
}

sub parse_user {
  my ($full) = @_;

  confess "parse_user() called with no arguments"
    unless defined $full;

  my ($nick, $user, $host) = split /[!@]/, $full;

  wantarray ? ($nick, $user, $host) : $nick
}

sub mode_to_hash {
  ## mode_to_hash( $string,
  ##   param_always => [ split //, 'bkov' ],
  ##   param_set    => [ 'l' ],
  ##   params       => [ ],
  ## )

  ## Returns HASH like:
  ##  add => {
  ##    'o' => [ 'some_nick' ],
  ##    't' => 1,
  ##  },
  ##  del => {
  ##    'k' => [ 'some_key' ],
  ##  },

  my $modestr = shift;
  confess "mode_to_hash() called with no mode string"
    unless $modestr;

  my %args = @_;
  $args{param_always} //= [ split //, 'bkov' ];
  $args{param_set}    //= [ 'l' ];
  $args{params}       //= [ ];
  for (qw/ param_always param_set params /) {
    confess "$_ should be an ARRAY"
      unless ref $args{$_} eq 'ARRAY';
  }

  my %param_always = map {; $_ => 1 } @{ $args{param_always} };
  my %param_set    = map {; $_ => 1 } @{ $args{param_set} };

  my $modes = { add => {}, del => {} };
  my @chunks = split //, $modestr;

  my $in = '+';
  PIECE: while (my $chunk = shift @chunks) {
    if ($chunk eq '-' || $chunk eq '+') {
      $in = $chunk;
      next PIECE
    }

    if ($in eq '+') {

      if (exists $param_always{$chunk} || exists $param_set{$chunk}) {
        ## Modes that have params always or when set.
        ## Value for this mode will be an ARRAY with one value.
        my $param = shift @{ $args{params} };
        carp "$chunk is in param_always or param_set but no param defined?"
          unless defined $param;
        $modes->{add}->{$chunk} = [ $param ];
      } else {
        ## ... otherwise, simple boolean true
        $modes->{add}->{$chunk} = 1;
      }

    } else {

      if (exists $param_always{$chunk}) {
        my $param = shift @{ $args{params} };
        carp "$chunk is in param_always modes but no param defined?"
          unless defined $param;
        $modes->{del}->{$chunk} = [ $param ];
      } else {
        $modes->{del}->{$chunk} = 1;
      }
    }

  }  ## PIECE


  $modes
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

=head3 mode_to_hash

  my $hash = mode_to_hash( 
    ## Mode change string without params, e.g. '+kl-t'
    $mode_string,

    ## Modes that always have a param:
    param_always => ARRAY,
    
    ## Modes that only have a param when set:
    param_set    => ARRAY,
    
    ## Respective params for modes specified above:
    params       => ARRAY,
  );

Given a mode string (without params) and some options, return a HASH with 
the keys B<add> and B<del>.

B<add> and B<del> are HASHes mapping mode characters to either a simple 
boolean true value or an ARRAY whose only element is the mode's 
parameters, e.g.:

  mode_to_hash( '+kl-t',
    params => [ 'key', 10 ],
    param_always => [ split //, 'bkov' ],
    param_set    => [ 'l' ],
  );

  ## Result:
  {
    add => {
      'l' => [ 10 ],
      'k' => [ 'key' ],
    },
    
    del => {
      't' => 1,
    },
  }

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
