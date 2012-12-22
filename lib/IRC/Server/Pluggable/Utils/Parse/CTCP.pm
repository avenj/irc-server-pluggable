package IRC::Server::Pluggable::Utils::Parse::CTCP;

use 5.12.1;
use strictures 1;
use Carp 'confess';

use Exporter 'import';
our @EXPORT = qw/
  ctcp_quote
  ctcp_unquote
/;

use IRC::Server::Pluggable 'IRC::Event';
use Scalar::Util 'blessed';

my %quote = (
  "\012" => 'n',
  "\015" => 'r',
  "\0"   => '0',
  "\cP"  => "\cP",
);
my %dequote = reverse %quote;

## Borrowed from POE::Filter::IRC::Compat  /  Net::IRC
##  Copyright BinGOs, fimm, Abigail et al

sub ctcp_quote {
  my ($line) = @_;
  confess "Expected a line" unless defined $line;

  if ($line =~ tr/[\012\015\0\cP]//) {
    $line =~ s/([\012\015\0\cP])/\cP$quote{$1}/g;
  }

  $line =~ s/\001/\\a/g;
  "\001$line\001";
}

sub ctcp_unquote {
  my ($line) = @_;
  confess "Expected a line" unless defined $line;

  if ($line =~ tr/\cP//) {
    $line =~ s/\cP([nr0\cP])/$dequote{$1}/g;
  }

  substr($line, rindex($line, "\001"), 1, '\\a')
    if ($line =~ tr/\001//) % 2 != 0;
  return unless $line =~ tr/\001//;

  my @chunks = split /\001/, $line;
  shift @chunks unless length $chunks[0];
  for (@chunks) {
    ## De-quote / convert escapes
    s/\\([^\\a])/$1/g;
    s/\\\\/\\/g;
    s/\\a/\001/g;
  }

  my (@ctcp, @text);

  ## If we start with a ctrl+A, the first chunk is CTCP:
  if (index($line, "\001") == 0) {
    push @ctcp, shift @chunks;
  }
  ## Otherwise we start with text and alternate CTCP:
  while (@chunks) {
    push @text, shift @chunks;
    push @ctcp, shift @chunks if @chunks;
  }

  +{ ctcp => \@ctcp, text => \@text }
}

sub ctcp_extract {
  my ($input) = @_;

  unless (blessed $input) {
    $input = ref $input ? ev(%$input) : ev(raw_line => $input);
  }

  my $type = uc($input->command) eq 'PRIVMSG' ? 'ctcp' : 'ctcpreply' ;
  my $line = $input->params->[1];
  my $unquoted = ctcp_unquote($line);
  return unless $unquoted;

  my ($name, $params);
  CTCP: for my $str ($unquoted->{ctcp}->[0]) {
    ($name, $params) = $str =~ /^(\w+)(?: +(.*))?/;
    last CTCP unless $name;
    $name = lc $name;
    if ($name eq 'dcc') {
      ## Does no extra work to parse DCC
      ## ... but see POE::Filter::IRC::Compat for that
      my ($dcc_type, $dcc_params) = $params =~ /^(\w+) +(.+)/;
      last CTCP unless $dcc_type;
      return ev(
        command => 'dcc_request_'.lc($dcc_type),
        params  => [
          $input->prefix,
          $dcc_params
        ],
        raw_line => $input->raw_line,
      )
    } else {
      return ev(
        command => $type .'_'. $name,
        params  => [
          $input->prefix,
          $input->params->[0],
          ( defined $params ? $params : '' ),
        ],
        raw_line => $input->raw_line,
      )
    }
  }
  return
}


1;

=pod

=head1 NAME

IRC::Server::Pluggable::Utils::Parse::CTCP - Parse incoming or outgoing CTCP

=head1 SYNOPSIS

FIXME

=head1 DESCRIPTION

Utility functions useful for quoting/unquoting/extracting CTCP.

=head2 ctcp_extract

Takes input (in the form of an L<IRC::Server::Pluggable::IRC::Event> instance,
a hash such as that produced by L<IRC::Server::Pluggable::IRC::Filter>, or a
raw line) and attempts to extract a valid CTCP request or reply.

Returns an L<IRC::Server::Pluggable::IRC::Event> whose C<command> carries an
appropriate prefix (one of B<ctcp>, B<ctcpreply>, or B<dcc_request>) prepended
to the CTCP command:

  $ev->command eq 'ctcp_version'      ## CTCP VERSION
    $ev->params would be sender, target(s), any additional params
  $ev->command eq 'ctcpreply_version' ## reply to CTCP VERSION
    $ev->params would be sender, target(s), contents of reply
  $ev->command eq 'dcc_request_send'  ## DCC SEND
    $ev->params would be sender and DCC parameters

Returns empty list if no valid CTCP was found.

=head2 ctcp_quote

CTCP quote a raw line.

=head2 ctcp_unquote

Deparses a raw line possibly containing CTCP.

Returns a hash with two keys, B<ctcp> and B<text>, whose values are 
ARRAYs containing the CTCP and text portions of a CTCP-quoted message.

=head1 AUTHOR

Code borrowed from L<POE::Filter::IRC::Compat>, copyright BinGOs, fimm et al

Licensed under the same terms as Perl.

=cut

