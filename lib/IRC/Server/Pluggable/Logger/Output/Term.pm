package IRC::Server::Pluggable::Logger::Output::Term;
use strictures 1;

sub USE_STDERR () { 0 }

use namespace::clean;

sub new {
  my $class = shift;
  my $self = [];
  bless $self, $class;
  my %params = @_;
  $self->use_stderr( $params{use_stderr} )
    if defined $params{use_stderr};
  $self
}

sub use_stderr {
  my ($self, $val) = @_;
  return $self->[USE_STDERR] = $val if defined $val;
  $self->[USE_STDERR]
}

sub _write {
  my ($self, $str) = @_;
  local $|=1;
  my $fh = $self->[USE_STDERR] ? *STDERR : *STDOUT ;
  binmode $fh, ":utf8";
  print {$fh} $str
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
      use_stderr => 0,
    },
  );

See L<IRC::Server::Pluggable::Logger::Output>.

=head1 DESCRIPTION

This is a L<IRC::Server::Pluggable::Logger::Output> writer for logging 
messages to STDOUT by default.

To log to STDERR instead, pass 'use_stderr => 1' when adding the output object.

Expects UTF-8.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
