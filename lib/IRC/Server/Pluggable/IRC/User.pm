package IRC::Server::Pluggable::IRC::User;
## Base class for Users.
## Overridable by Protocols.

## FIXME stringify out to (lowercased?) nickname?

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable qw/
  Types
  Utils
/;

has 'nick' => (
  required => 1,
  is  => 'ro',
  isa => Str,
  writer => 'set_nick',
);

has 'user' => (
  required => 1,
  is  => 'ro',
  isa => Str,
  writer => 'set_user',
);

has 'host' => (
  required => 1,
  is  => 'ro',
  isa => Str,
  writer => 'set_host',
);

has 'server' => (
  required => 1,
  is  => 'ro',
  isa => Str,
  writer => 'set_server',
);

has 'realname' => (
  required => 1,
  is  => 'ro',
  isa => Str,
  writer => 'set_realname',
);

has 'modes' => (
  lazy => 1,
  is  => 'ro',
  isa => HashRef,
  default => sub { {} },
);


sub full {
  my ($self) = @_;
  $self->nick .'!'. $self->user .'@'. $self->host
}

sub set_modes {
  my ($self, $data) = @_;

  my %changed;
  
  if (ref $data eq 'ARRAY') {

    MODE: for my $mode (@$data) {
      my ($chg, $flag) = $mode =~ /^(+|-)([A-Za-z])$/;

      unless ($chg && $flag) {
        carp "Could not parse mode change $mode";
        next MODE
      }
      
      ## Boolean flip.
      if ($chg eq '+') {
        unless ($self->modes->{$flag}) {
          ## Add this mode and record the change.
          $self->modes->{$flag} = 1;
          $changed{$flag} = 1;
        }
      } elsif ($chg eq '-') {
        if ($self->modes->{$flag}) {
          ## Delete this mode and record the change.
          $changed{$flag} = delete $self->modes->{$flag};
        }
      }

    } ## MODE

  } elsif (ref $data eq 'HASH') {
    ## FIXME hash-based implementation?
    confess "Passing set_modes a HASH not implemented in this class"
  } else {
    ## Probably a string.
    ## FIXME shove parser for this in Utils?
  }

  \%changed
}


q{
  <Schroedingers_hat> i suppose I could analyse the gif and do a fourier 
   decomposition, then feed that into a linear model and see what 
   happens...
  <Schroedingers_hat> ^ The best part is that sentence was 
   about breasts.
};
