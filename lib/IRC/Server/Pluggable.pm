package IRC::Server::Pluggable;
our $VERSION = '0.000_01';

use strictures 1;

use Carp 'confess';
use Module::Runtime 'use_module';

use namespace::clean;

sub import {
  my ($self, @modules) = @_;

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

  { no strict 'refs';
    *{ $pkg .'::prefixed_new' } = sub {
        my $suffix  = 
          shift || confess "Expected a package name without prefix";
        my $thispkg = 'IRC::Server::Pluggable::'.$suffix;
        require $thispkg;
        $thispkg->new(@_)
    };
  }
  

  confess "Failed to import ".join ' ', @failed
    if @failed;

  1
}

sub create {
  my (undef, $module) = splice @_, 0, 2;
  confess "Expected a module name and optional params"
    unless defined $module;
  my $real = join '::', __PACKAGE__, $module;
  use_module($real)->new(@_)
}


1;

=pod

=head1 NAME

IRC::Server::Pluggable - POE IRC server building blocks

=head1 SYNOPSIS

FIXME

=head1 DESCRIPTION

A pluggable, extensible IRCd stack using L<Moo>, L<POE>, and 
L<MooX::Role::POE::Emitter>.

  ::Protocol::Base (Emitter)
  |
  |   ::Protocol::Role::
  |  /
  ::Protocol
  |
  |
   \ ::Dispatcher (Emitter)
     |
      \ ::Backend  (Session / Component)

An ongoing project; help is welcome, discussion can take place on 
C<irc.cobaltirc.org #eris>

=head1 SEE ALSO


L<IRC::Server::Pluggable::IRC::Filter> - IRCv3-ready IRC filter

L<IRC::Server::Pluggable::IRC::Protocol>

L<IRC::Server::Pluggable::IRC::Channels>

L<IRC::Server::Pluggable::IRC::Users>

L<IRC::Server::Pluggable::IRC::Peers>

L<MooX::Role::POE::Emitter>

L<MooX::Role::Pluggable>

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
