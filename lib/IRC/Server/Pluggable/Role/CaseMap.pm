package IRC::Server::Pluggable::Role::CaseMap;

use strictures 1;
use Carp;

use Moo::Role;


sub __get_cmap {
  my ($self) = @_;

  $self->can('protocol') ? $self->protocol->casemap
   : $self->can('casemap') ? $self->casemap
    : confess "Could not retrieve casemap()"
}

sub lower {
  my ($self, $name) = @_;

  unless (defined $name) {
    carp "lower() called with no channel name specified";
    return
  }

  lc_irc( $name, $self->__get_cmap )
}

sub upper {
  my ($self, $name) = @_;

  unless (defined $name) {
    carp "upper() called with no channel name specified";
    return
  }

  uc_irc( $name, $self->__get_cmap )
}

sub equal {
  my ($self, $one, $two) = @_;

  unless (defined $one && defined $two) {
    carp "equal() called without enough arguments";
    return
  }

  $self->upper($one) eq $self->upper($two) ? 1 : 0
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

See L<IRC::Server::Pluggable::Utils/"lc_irc"> for details on IRC case 
sensitivity issues.

C<requires> attribute B<casemap>.

=head2 lower

  my $lower = $self->lower($string);

Apply C<lc_irc> to a string using the available B<casemap>.

=head2 upper

  my $upper = $self->upper($string);

Reverse of L</"lower">.

=head2 equals

  if ( $self->equals($string_one, $string_two) ) {

   . . . 

  }

Determine whether the strings match case-insensitively (using available 
B<casemap>).

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
