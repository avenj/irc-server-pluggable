package IRC::Server::Pluggable::Utils::Format;
use 5.12.1;
use strictures 1;

use parent 'Exporter';

our @EXPORT = qw/
  templatef
/;

sub templatef {
  my $string = shift;
  return '' unless defined $string and length $string;

  my %vars;
  if (@_ > 1) {
    %vars = @_;
  } else {
    %vars = ref $_[0] eq 'HASH' ? %{$_[0]} : ()
  }

  my $rpl = sub {
    my ($orig, $match) = @_;
    if (defined $vars{$match}) {
      return ref $vars{$match} eq 'CODE' ?
        $vars{$match}->($match, $orig, $vars{$match})
        : $vars{$match}
    }
    $orig
  };

  my $re = qr/(%([^\s%]+)%?)/;
  $string =~ s/$re/$rpl->($1, $2)/ge;

  $string
}

1;

=pod

=head1 NAME

IRC::Server::Pluggable::Utils::Format - Templated string formatter

=head1 SYNOPSIS

  my $things = "some very special";
  my $formatted = templatef( "My %string% with %this% var",
    this   => $things,
    string => "cool string",
  );  ## -> My cool string with some very special var

=head1 DESCRIPTION

A tiny string formatter.

Exports a single function called B<templatef> which takes a string and a 
hash (or hash reference) mapping template variables to replacement strings.

The replacement variables can be coderefs returning a string:

  templatef( "My string with %code",
    code => sub {
      my ($match, $orig, $callback) = @_;
      . . .
      return "Some string replacing variable $match"
    },
  );

The code reference will receive the matching variable ("code"), the original matched
string ("%code" in the above example), and itself as its respective arguments.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
