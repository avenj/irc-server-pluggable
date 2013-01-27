package IRC::Server::Pluggable::Role::CaseMap;

use strictures 1;
use Carp;

use Moo::Role;

use IRC::Toolkit::Case;

use namespace::clean;

requires 'casemap';

sub lower {
  my ($self, $name) = @_;

  confess "lower() called with no channel name specified"
    unless defined $name;

  lc_irc( $name, $self->casemap )
}

sub upper {
  my ($self, $name) = @_;

  confess "upper() called with no channel name specified"
    unless defined $name;

  uc_irc( $name, $self->casemap )
}

sub equal {
  my ($self, $one, $two) = @_;

  confess "equal() called without enough arguments"
    unless defined $one and defined $two;

  my $casemap = $self->casemap;
  uc_irc($one, $casemap) eq uc_irc($two, $casemap) ? 1 : ()
}


1;

=pod

=head1 NAME

IRC::Server::Pluggable::Role::CaseMap - IRC casemap-aware lc/uc

=head1 SYNOPSIS

  use Moo;

  has 'casemap' => (
    is  => 'ro',

    isa => sub {
      my $value = $_[0];
      defined $value
        and (grep { $_ eq $value} qw/rfc1459 strict-rfc1459 ascii/)
        or die "$_[0] is not a known valid IRC casemap"
    },

    default => sub { "rfc1459" },
  );

  with 'IRC::Server::Pluggable::Role::CaseMap';

=head1 DESCRIPTION

A L<Moo::Role> providing casemap-related functions that are aware of the 
B<casemap()> attribute belonging to the consuming class.

Requires attrib 'casemap' which should be one of:

  rfc1459
  strict-rfc1459
  ascii

See L<IRC::Server::Pluggable::Utils/"lc_irc"> for details on IRC case 
sensitivity issues.

=head2 lower

  my $lower = $self->lower($string);

Apply C<lc_irc> to a string using the available B<casemap>.

=head2 upper

  my $upper = $self->upper($string);

Reverse of L</"lower">.

=head2 equal

  if ( $self->equal($string_one, $string_two) ) {

   . . . 

  }

Determine whether the strings match case-insensitively (using available 
B<casemap>).

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
