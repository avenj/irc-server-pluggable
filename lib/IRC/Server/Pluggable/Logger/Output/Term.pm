package IRC::Server::Pluggable::Logger::Output::Term;
our $VERSION = '0.014';

use strictures 1;

sub new {
  my $class = shift;
  my $self = [];
  bless $self, $class;
  $self
}

sub _write {
  my ($self, $str) = @_;
  local $|=1;
  binmode STDOUT, ":utf8";
  print STDOUT $str
}

1;
__END__

=pod

=head1 NAME

IRC::Server::Pluggable::Logger::Output::Term

=head1 SYNOPSIS

  $output_obj->add(
    'MyScreen' => {
      type => 'Term',
    },
  );

See L<IRC::Server::Pluggable::Logger::Output>.

=head1 DESCRIPTION

This is a L<IRC::Server::Pluggable::Logger::Output> writer for logging messages to 
STDOUT.

Expects UTF-8.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
