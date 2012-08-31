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
  {
    name => 'IRC_Username',
    test => \&test_valid_name,
    message => sub { "$_[0] is not a valid IRC username" },
  },
  {
    name => 'IRC_Hostname',
    test => \&test_valid_hostname,
    message => sub { "$_[0] is not a valid IRC hostname" },
  },


  ## Misc
  {
    name => 'InetProtocol',
    test => sub { $_[0] && $_[0] == 4 || $_[0] == 6 },
    message => sub { "$_[0] is not inet protocol 4 or 6" },
  },
];

sub test_valid_username {
  my ($str) = @_;

  return unless defined $str and length $str;

  ## Skip leading ~
  substr($str, 0, 1, '') if index($str, '~') == 0;

  ## Must start with alphanumeric
  ## Valid: A-Z 0-9 . - $ [ ] \ ^ _ ` { } ~ |
  ## This is a pretty loose definition matching oftc-hybrid-1.6.7
  return unless $str =~ /^[A-Za-z0-9][A-Za-z0-9.\-\$\[\]\\^_`\|\{}~]+$/;

  1
}

sub test_valid_hostname {
  my ($str) = @_;

  return unless defined $str and length $str;

  ## OK, so { } aren't standard.
  ## ... but oftc-hybrid/bc6 allows them for user cloaks.
  ## Whether that's a good idea or not . . . well.
  return unless $str =~ /^[A-Za-z0-9\|\-.\/:^\{}]+$/;

  1
}

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
