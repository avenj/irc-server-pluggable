package IRC::Server::Pluggable::Role::Routable;

use Moo::Role;
use strictures 1;
use Carp 'confess';
use Scalar::Util 'blessed';

has 'conn' => (
  lazy      => 1,
  ## Typically tracked in Backend:
  weak_ref  => 1,
  is        => 'ro',
  predicate => 'has_conn',
  writer    => 'set_conn',
  clearer   => 'clear_conn',
  isa       => sub {
    my $wantclass = "POEx::IRC::Backend::Connect";
    blessed($_[0]) and $_[0]->isa($wantclass)
      or confess "$_[0] is not a $wantclass"
  },
);

has 'route' => (
  lazy      => 1,
  is        => 'ro',
  predicate => 'has_route',
  writer    => 'set_route',
  clearer   => 'clear_route',
  isa       => sub {
    defined $_[0] and length "$_[0]"
      or confess "Expected a route ID string, got $_[0]"
  },
  default   => sub {
    my ($self) = @_;
    ## A local connect should have a wheel_id
    ## A remote connect should have a route specified at build time
    ## A BUILD method to verify has_conn || has_route is advisable
    $self->conn->wheel_id
  },
);

1;

=pod

=head1 NAME

IRC::Server::Pluggable::Role::Routable

=head1 SYNOPSIS

FIXME

=head1 DESCRIPTION

A Role whose consumer receives attributes defining a route and potentially a
directly-attached L<POEx::IRC::Backend::Connect> object.

=head2 conn

FIXME

=head2 route

FIXME

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
