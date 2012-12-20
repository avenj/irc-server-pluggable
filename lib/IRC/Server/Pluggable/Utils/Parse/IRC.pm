package IRC::Server::Pluggable::Utils::Parse::IRC;
use Carp 'confess';
use strictures 1;

## Functional interface to our IRC::Filter
require IRC::Server::Pluggable::IRC::Filter;

use Exporter 'import';
our @EXPORT = qw/
  irc_ref_from_line
  irc_line_from_ref
/;


my $filter = 'IRC::Server::Pluggable::IRC::Filter';

sub irc_ref_from_line {
  my $line = shift;
  confess "Expected a line and optional filter arguments"
    unless $line;
  $filter->new(@_)->get([$line])->[0]
}

sub irc_line_from_ref {
  my $ref = shift;
  confess "Expected a HASH and optional filter arguments"
    unless ref $ref eq 'HASH';
  $filter->new(@_)->put([$ref])->[0]
}


1;

=pod

=head1 NAME

IRC::Server::Pluggable::Utils::Parse::IRC - Functional IRC::Filter frontend

=head1 SYNOPSIS

  use IRC::Server::Pluggable qw/
    Utils::Parse::IRC
  /;

  my $ref = irc_ref_from_line( $raw_irc_line );
  my $raw_line = irc_line_from_ref( $ref, colonify => 1 );

=head1 DESCRIPTION

A simple functional frontend to the L<IRC::Server::Pluggable::IRC::Filter>
IRCv3 L<POE::Filter>.

Options can be passed directly to the filter (see L</SYNOPSIS>).

See L<IRC::Server::Pluggable::IRC::Filter> for details on the references
returned.

Also see L<IRC::Server::Pluggable::IRC::Event> for an object interface capable
of transforming IRC events/lines.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
