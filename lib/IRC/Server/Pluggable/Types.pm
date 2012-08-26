package IRC::Server::Pluggable::Types;

use strictures 1;

use base 'Exporter';
use MooX::Types::MooseLike;
use MooX::Types::MooseLike::Base qw/:all/;

our @EXPORT_OK = ();

use Scalar::Util qw/blessed/;

my $type_definitions = [
  ## POE bits
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

  ## Our classes
  {
    name => 'BackendClass',
    test => sub {
      blessed($_[0])
      && $_[0]->isa('IRC::Server::Pluggable::Backend')
    },
    message => sub { "$_[0] is not a IRC::Server::Pluggable::Backend" },
  },
  {
    name => 'ProtocolClass',
    test => sub {
      blessed($_[0])
      && $_[0]->isa('IRC::Server::Pluggable::Protocol')
    },
    message => sub { "$_[0] is not a IRC::Server::Pluggable::Protocol" },
  },

  ## IRC bits
  {
    name => 'CaseMap',
    test => sub {
      is_Str($_[0]) &&
      (
       $_[0] eq 'rfc1459'
       || $_[0] eq 'ascii'
       || $_[0] eq 'strict-rfc1459'
      )
    },
    message => sub {
     "$_[0] is not a valid IRC casemap, "
     ."should be one of: rfc1459, ascii, strict-rfc1459"
    },
  },
  {
    name => 'IRC_Nickname',
    test => sub {
      is_Str($_[0]) && length($_[0]) &&
      ## Regexp borrowed from IRC::Utils
      $_[0] =~ /^[A-Za-z_`\-^\|\\\{}\[\]][A-Za-z_0-9`\-^\|\\\{}\[\]]*$/;
    },
    message => sub { "$_[0] is not a valid IRC nickname" },
  },


  ## Misc
  {
    name => 'InetProtocol',
    test => sub { $_[0] && $_[0] == 4 || $_[0] == 6 },
    message => sub { "$_[0] is not inet protocol 4 or 6" },
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

=pod


=cut
