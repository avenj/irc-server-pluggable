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

  confess "set_modes() called with no defined arguments"
    unless defined $data;

  $data = $self->_parse_mode_str($data)
    unless ref $data;

  $self->_set_modes_from_ref($data)
}

sub _set_modes_from_ref {
  my ($self, $data) = @_;

  my %changed;
  
  if (ref $data eq 'ARRAY') {
  
    MODE: for my $mode (@$data) {

      ## Accept [ $flag, $params ] -- default to bool
      my $params = 1;
      if (ref $mode eq 'ARRAY') {
        ($mode, $params) = @$mode;
      }
    
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
          $changed{$flag}       = 1;
        }
      } elsif ($chg eq '-') {
        if ($self->modes->{$flag}) {
          ## Delete this mode and record the change.
          $changed{$flag} = delete $self->modes->{$flag};
        }
      }

    } ## MODE

  } elsif (ref $data eq 'HASH') {

    ## add => [ mode, ... ],
    ## add => [ [ mode, params ], ... ],
    ## del => [ mode, ... ],
    
    ADD: for my $flag (@{ $ref->{add} }) {
      my $params = 1;
      if (ref $flag eq 'ARRAY') {
        ($flag, $params) = @$flag;
      }

      unless ($self->modes->{$flag} 
        && $self->modes->{$flag} eq $params) {

        $self->modes->{$flag} = $params;
        $changed{$flag}       = $params;
      }

    }
    
    DEL: for my $flag (@{ $ref->{del} }) {
      if ($self->modes->{$flag}) {
        $changed{$flag} = delete $self->modes->{$flag};
      }
    }

  } else {
    confess "Passed an unknown reference type: ".ref($data)." ($data)"
  }

  \%changed
}

sub _parse_mode_str {
  my ($self, $str) = @_;

  my %res = ( add => [], del => [] );
  
  my $in_add = 1;
  for (split '', $str) {
    when ('+') {
      $in_add = 1;
    }
    
    when ('-') {
      $in_add = 0;
    }
    
    when (/A-Za-z/) {
      if ($in_add) {
        push(@{$res{add}}, $_)
      } else {
        push(@{$res{del}}, $_)
      }
    }
    
    default {
      carp "Could not parse mode change $_ in $str";
    }
  }
  
  \%res
}


q{
  <Schroedingers_hat> i suppose I could analyse the gif and do a fourier 
   decomposition, then feed that into a linear model and see what 
   happens...
  <Schroedingers_hat> ^ The best part is that sentence was 
   about breasts.
};
