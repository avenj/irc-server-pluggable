package IRC::Server::Pluggable::IRC::Users;

## Maintain a collection of User objects.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable qw/
  Types
  Utils
/;


has 'casemap' => (
  required => 1,
  is  => 'ro',
  isa => CaseMap,
);

with 'IRC::Server::Pluggable::Role::CaseMap';


has '_users' => (
  ## Map (lowercased) nicknames to User objects.
  lazy => 1,
  is   => 'ro',
  isa  => HashRef,
  default => sub { {} },  
);


q{
 <hypervalent_iodine> The people who irk me the most are the ones who use 
  anecdotal evidence as some sort of unfalsifiable proof   
 <Schroedingers_hat> But I used anecdotal evidence once, and it turned 
  out I was right.
};


=pod

=cut
