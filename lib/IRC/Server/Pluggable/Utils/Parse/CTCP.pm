package IRC::Server::Pluggable::Utils::Parse::CTCP;

use 5.12.1;
use strictures 1;
use Carp 'confess';

use Exporter 'import';
our @EXPORT = qw/
  ctcp_quote
  ctcp_unquote
/;

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
  ## FIXME
  ##  ctcp_unquote and extract first CTCP
  ##   return Event?
}


1;
