package IRC::Server::Pluggable::Constants;
our $VERSION = '0.000_01';

use strictures 1;

use constant {
  EAT_NONE   => 1,
  EAT_CLIENT => 2,
  EAT_PLUGIN => 3,
  EAT_ALL    => 4,

  DISPATCH_EATEN   => 5,
  DISPATCH_CALLED  => 6,
  DISPATCH_UNKNOWN => 7,
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

Exports constants used by L<IRC::Server::Pluggable::Role::Pluggable> and
L<IRC::Server::Pluggable::Role::Emitter>:

  EAT_NONE   => 1
  EAT_CLIENT => 2
  EAT_PLUGIN => 3
  EAT_ALL    => 4

Exports constants used internally by L<IRC::Server::Pluggable::Protocol::Base>:

  DISPATCH_EATEN   => 5
  DISPATCH_CALLED  => 6
  DISPATCH_UNKNOWN => 7

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>


=cut
