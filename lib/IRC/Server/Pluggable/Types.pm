package IRC::Server::Pluggable::Types;

use strictures 1;

use base 'Exporter';
use MooX::Types::MooseLike::Base;

our @EXPORT_OK;

use Scalar::Util qw/blessed/;

my $type_definitions = [
  {
    name => 'Wheel',
    test => sub { blessed($_[0]) && $_[0]->isa('POE::Wheel') },
    message => sub { "$_[0] is not a POE::Wheel" },
  },
];

MooX::Types::MooseLike::register_types(
  $type_definitions, __PACKAGE__
);

our @EXPORT = \@EXPORT_OK;

1;
