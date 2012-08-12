package IRC::Server::Pluggable::IRC::Channels;

## Maintain a collection of Channel objects.

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



has '_channels' => (
  ## Map (lowercased) channel names to Channel objects.
  lazy => 1,
  
  is  => 'ro',
  isa => HashRef,
  
  default => sub { {} },
);





q{
 <Capn_Refsmmat> Gilded: Have you considered employment as a cheap 
   punster?   
  <Gilded> Pun good - make many pun is good for brain, also 
   then make better English in future times
  <Gilded> I also take slight offense at "cheap" considering all my puns 
   are solid gold
};


=pod

=cut
