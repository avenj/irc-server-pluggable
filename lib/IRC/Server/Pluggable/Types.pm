package IRC::Server::Pluggable::Types;

use strictures 1;

use base 'Exporter';
use MooX::Types::MooseLike;
use MooX::Types::MooseLike::Base qw/:all/;

our @EXPORT_OK = ();

use Scalar::Util qw/blessed/;

my $type_definitions = [
  {
    name => 'Wheel',
    test => sub { blessed($_[0]) && $_[0]->isa('POE::Wheel') },
    message => sub { "$_[0] is not a POE::Wheel" },
  },
  {

    name => 'Filter',
    test => sub { blessed($_[0]) && $_[0]->isa('POE::Filter') },
    message => sub { "$_[0] is not a POE::Filter" },
  },

  {
    name => 'InetProtocol',
    test => sub { $_[0] && $_[0] == 4 || $_[0] == 6 },
    message => sub { "$_[0] is not inet protocol 4 or 6" },
  },
  
  {
    name => 'Backend',
    test => sub { 
      blessed($_[0]) 
      && $_[0]->isa('IRC::Server::Pluggable::Backend')
    },
    message => sub { "$_[0] is not a IRC::Server::Pluggable::Backend" },
  },
];

MooX::Types::MooseLike::register_types(
  $type_definitions, __PACKAGE__
);

our @EXPORT = (
  @EXPORT_OK,
  @MooX::Types::MooseLike::Base::EXPORT_OK
);

1;
