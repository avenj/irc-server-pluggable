package IRC::Server::Pluggable;
our $VERSION = '0.000_01';

use 5.12.1;
use strictures 1;

use Carp;

sub import {
  my $self = shift;
  my @modules = @_;

  my $pkg = caller;

  my @failed;

  for my $module (@modules) {
    my $c =
      "package $pkg; use IRC::Server::Pluggable::$module;" ;

    eval $c;
    if ($@) {
      warn $@;
      push @failed, $module;
    }
  }

  confess "Failed to import ".join ' ', @failed
    if @failed;

  1
}

1;

=pod

=head1 NAME

IRC::Server::Pluggable - POE IRC server building blocks

=head1 SYNOPSIS

FIXME

=head1 DESCRIPTION

A pluggable, extensible IRCd stack using L<Moo>, L<POE>, and 
L<Object::Pluggable>.

FIXME

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
