package IRC::Server::Pluggable;
use feature 'state';
use strictures 1;

use Carp 'confess';
use Module::Runtime 'require_module';

use namespace::clean;

my $prefix_new_sub = sub {
  my $suffix = shift || confess "Expected a package name without prefix";
  my $thispkg = 'IRC::Server::Pluggable::'.$suffix;
  require_module($thispkg);
  $thispkg->new(@_)
};


sub import {
  my (undef, @modules) = @_;
  my $pkg = caller;
  my @failed;

  for my $module (@modules) {
    if ($module eq 'Types') {
      $module = "$module -all";
      state $guard = do { require_module('Type::Registry') };
      eval {; 
        Type::Registry->for_class($pkg)->add_types(
          __PACKAGE__ .'::Types'
        )
      };
      warn $@ if $@;
    }

    my $c =
      "package $pkg; use IRC::Server::Pluggable::$module;" ;

    eval $c;
    if ($@) {
      warn $@;
      push @failed, $module;
    }
  }

  { no strict 'refs';
    *{ $pkg .'::prefixed_new' } = $prefix_new_sub;
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


=head2 EXPORTED

=head3 prefixed_new

  my $user = prefixed_new( 'IRC::User' => @params );

The above would be equivalent to:

  require IRC::Server::Pluggable::IRC::User;
  my $user = IRC::Server::Pluggable::IRC::User->new(@params);

=head1 SEE ALSO

L<IRC::Server::Pluggable::IRC::Dispatcher>

L<IRC::Server::Pluggable::IRC::Protocol>

L<IRC::Server::Pluggable::IRC::Channels>

L<IRC::Server::Pluggable::IRC::Users>

L<IRC::Server::Pluggable::IRC::Peers>

L<IRC::Toolkit>

L<MooX::Role::POE::Emitter>

L<MooX::Role::Pluggable>

L<POE::Filter::IRCv3>

L<POEx::IRC::Backend>

L<POEx::IRC::Client::Lite>

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
