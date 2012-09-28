package IRC::Server::Pluggable::Types;

use strictures 1;

use base 'Exporter';
use MooX::Types::MooseLike;
use MooX::Types::MooseLike::Base qw/:all/;

our @EXPORT_OK;

use Scalar::Util 'blessed';

my $type_definitions = [
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
    test => \&test_valid_nickname,
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

sub test_valid_nickname {
  my ($str) = @_;

  return unless defined $str and length $str;

  return unless
    $str =~ /^[A-Za-z_`\-^\|\\\{}\[\]][A-Za-z_0-9`\-^\|\\\{}\[\]]*$/;

  1
}

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

  return unless $str =~ /^[A-Za-z0-9\|\-.\/:]+$/;

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

=head1 NAME

IRC::Server::Pluggable::Types - MooX::Types::MooseLike and extras

=head1 SYNOPSIS

  use IRC::Server::Pluggable::Types;

  has 'nick' => (
    is  => 'ro',
    isa => IRC_Nickname,
  );

  has 'user' => (
    is  => 'ro',
    isa => IRC_Username,
  );

=head1 DESCRIPTION

This module exports all types from L<MooX::Types::MooseLike>, plus the
following additional types:

=head2 Misc

=head3 InstanceOf

  isa => InstanceOf['IRC::Server::Pluggable::Protocol::Base'];

Parameterized type that checks L<UNIVERSAL/isa>.

Expects an object whose inheritance tree contains the specified class.

=head3 InetProtocol

  isa => InetProtocol,

Expects an integer representing Internet protocol '4' or '6'

=head2 IRC

=head3 CaseMap

Expects a valid IRC CaseMap, one of:

  ascii
  rfc1459
  strict-rfc1459

=head3 IRC_Hostname

Expects a valid hostname.

=head3 IRC_Nickname

Expects a valid nickname per RFC1459.

=head3 IRC_Username

Expects a valid username.

Usernames must begin with an alphanumeric value.

Valid: A-Z 0-9 . - $ [ ] \ ^ _ ` { } ~ |

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
