package IRC::Server::Pluggable::Protocol::TS6::User;
## ISA IRC::Server::Pluggable::IRC::User

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

extends 'IRC::Server::Pluggable::IRC::User';

has 'ts' => (
  required => 1,
  
  is  => 'ro',
  isa => Num,
  
  writer => 'set_ts',
);

has 'id' => (
  required => 1,
  
  is  => 'ro',
  isa => sub {
    $_[0] =~ /^[A-Z][A-Z0-9]+$/
      or die "$_[0] does not look like a valid TS6 ID"
  },
  
  writer => 'set_id',
);

has 'uid' => (
  ## Per TS6.txt: ( UID = SID . id() )
  required => 1,

  is  => 'ro',
  isa => sub {
    $_[0] =~ /^[A-Z][A-Z0-9]+$/
      or die "$_[0] does not look like a valid TS6 UID"
  },

  writer => 'set_uid',
);


1;
