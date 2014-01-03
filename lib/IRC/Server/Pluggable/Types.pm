package IRC::Server::Pluggable::Types;
use strictures 1;

use Type::Library    -base;
use Type::Utils      -all;
use Types::Standard  -types;
use Types::TypeTiny  ();


declare CaseMap =>
  as Str(),
  where {
    $_ eq 'rfc1459' || $_ eq 'ascii' || $_ eq 'strict-rfc1459'
  },
  inline_as {
    my ($constraint, $cmap) = @_;
    $constraint->parent->inline_check($cmap) . qq{
      && ($cmap eq 'rfc1459' || $cmap eq 'ascii' || $cmap eq 'strict-rfc1459')
    }
  };

declare IRC_Nickname =>
  as Str(),
  where {
    $_ =~ /^[A-Za-z_`\-^\|\\\{}\[\]][A-Za-z_0-9`\-^\|\\\{}\[\]]*$/
  },
  inline_as {
    my ($constraint, $var) = @_;
    my $re = '^[A-Za-z_`\-^\|\\\{}\[\]][A-Za-z_0-9`\-^\|\\\{}\[\]]*$';
    $constraint->parent->inline_check($var) . qq{
      && ($var =~ /$re/)
    }
  };

declare IRC_Username =>
  as Str(),
  where {
    ## Must start with alphanumeric
    ## Valid: A-Z 0-9 . - $ [ ] \ ^ _ ` { } ~ |
    ## This is a pretty loose definition matching oftc-hybrid-1.6.7
    $_ =~ /^~?[A-Za-z0-9][A-Za-z0-9.\-\$\[\]\\^_`\|\{}~]+$/
  },
  inline_as {
    my ($constraint, $var) = @_;
    my $re = '^~?[A-Za-z0-9][A-Za-z0-9.\-\$\[\]\\^_`\|\{}~]+$';
    $constraint->parent->inline_check($var) . qq{
      && ($var =~ /$re/)
    }
  };

declare IRC_Hostname =>
  as Str(),
  where {
    $_ =~ /^[A-Za-z0-9\|\-.\/:]+$/
  },
  inline_as {
    my ($constraint, $var) = @_;
    my $re = '^[A-Za-z0-9\|\-.\/:]+$';
    $constraint->parent->inline_check($var) . qq{
      && ($var =~ /$re/)
    }
  };

declare TS_ID =>
  as Str(),
  where {
    $_ =~ /^[A-Z][A-Z0-9]+$/
  },
  inline_as {
    my ($constraint, $var) = @_;
    my $re = '^[A-Z][A-Z0-9]+$';
    $constraint->parent->inline_check($var) . qq{ 
      && ($var =~ /$re/)
    }
  };

declare InetProtocol =>
  as Int(),
  where {
    $_ == 4 || $_ == 6
  },
  inline_as {
    my ($constraint, $var) = @_;
    $constraint->parent->inline_check($var) . qq{
      && ($var == 4 || $var == 6)
    }
  };


# FIXME POD
declare ChanObj =>
  as InstanceOf['IRC::Server::Pluggable::IRC::Channel'];

declare UserObj =>
  as InstanceOf['IRC::Server::Pluggable::IRC::User'];

declare PeerObj =>
  as InstanceOf['IRC::Server::Pluggable::IRC::Peer'];


print
q{ <Gilded> I've actually worked at an archeological dig for a while
 <Gilded> It was kind of, well, meh
 <Capn_Refsmmat> Gilded: What have you experienced that wasn't meh?
 <Gilded> Well this one time I critted someone for 32k damage in WoW
} unless caller;


=pod

=head1 NAME

IRC::Server::Pluggable::Types - Type::Tiny types for IRC servers

=head1 SYNOPSIS

  use IRC::Server::Pluggable 'Types';

  has 'nick' => (
    is  => 'ro',
    isa => IRC_Nickname,
  );

  has 'user' => (
    is  => 'ro',
    isa => IRC_Username,
  );

=head1 DESCRIPTION

L<IRC::Server::Pluggable> types.

Importing via L<IRC::Server::Pluggable>, as shown in the SYNOPSIS, will also
attempt to register with L<Type::Registry>.

=head3 InetProtocol

  isa => InetProtocol,

Expects an integer representing Internet protocol '4' or '6'

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
