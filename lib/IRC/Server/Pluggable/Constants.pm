package IRC::Server::Pluggable::Constants;
our $VERSION = '0.000_01';

use strictures 1;

use constant {
  DISPATCH_EATEN   => 1,
  DISPATCH_CALLED  => 2,
  DISPATCH_UNKNOWN => 3,

  EAT_NONE   => 1,
  EAT_CLIENT => 2,
  EAT_PLUGIN => 3,
  EAT_ALL    => 4,
};

use base 'Exporter';

our @EXPORT = qw/
  DISPATCH_EATEN
  DISPATCH_CALLED
  DISPATCH_UNKNOWN

  EAT_NONE
  EAT_CLIENT
  EAT_PLUGIN
  EAT_ALL
/;


1;

=pod

=head1 NAME

IRC::Server::Pluggable::Constants

=head1 SYNOPSIS

  use IRC::Server::Pluggable qw/
    Constants
  /;

=head1 DESCRIPTION

Exports constants used by L<IRC::Server::Pluggable::Protocol>:

  DISPATCH_EATEN   => 1
  DISPATCH_CALLED  => 2
  DISPATCH_UNKNOWN => 3

Exports constants from L<Object::Pluggable::Constants> (but with 
slightly less typing):

  EAT_NONE   => 1
  EAT_CLIENT => 2
  EAT_PLUGIN => 3
  EAT_ALL    => 4

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>


=cut
