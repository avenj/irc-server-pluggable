package IRC::Server::Pluggable::Constants;
our $VERSION = 1;

## Object::Pluggable::Constants, but less typing.

use strictures 1;

use constant {
  EAT_NONE   => 1,
  EAT_CLIENT => 2,
  EAT_PLUGIN => 3,
  EAT_ALL    => 4,
};

use base 'Exporter';

our @EXPORT = qw/
  EAT_NONE
  EAT_CLIENT
  EAT_PLUGIN
  EAT_ALL
/;

q{
 <bob2> your question is similar to "why can't I jam burritos in my 
  earholes"
 <bob2> the answer is "well, you can, but it's a fucking 
  stupid idea that won't help you make your crappy php forum work"
};

=pod

=head1 NAME

IRC::Server::Pluggable::Constants

=head1 SYNOPSIS

  use IRC::Server::Pluggable qw/
    Constants
  /;

=head1 DESCRIPTION

Exports constants from L<Object::Pluggable::Constants> (but with 
slightly less typing):

  EAT_NONE   => 1
  EAT_CLIENT => 2
  EAT_PLUGIN => 3
  EAT_ALL    => 4

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>


=cut
