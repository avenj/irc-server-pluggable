package IRC::Server::Pluggable;
our $VERSION = '0.001';

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
