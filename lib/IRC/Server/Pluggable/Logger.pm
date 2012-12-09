package IRC::Server::Pluggable::Logger;
use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use Scalar::Util 'blessed';

use IRC::Server::Pluggable qw/
  Logger::Output
  Types
/;

use namespace::clean;


has 'level' => (
  required  => 1,
  is        => 'ro',
  writer    => 'set_level',
  isa       => sub {
    my $lev = $_[0];
    confess "Unknown log level, should be one of: error warn info debug"
      unless grep {; $_ eq $lev } qw/error warn info debug/;
  },
);


## time_format / log_format are passed to ::Output
has 'time_format' => (
  lazy      => 1,
  is        => 'ro',
  isa       => Str,
  predicate => 'has_time_format',
  writer    => 'set_time_format',
  trigger => sub {
    my ($self, $val) = @_;
    $self->output->time_format($val) if $self->has_output;
  },
);


has 'log_format' => (
  lazy      => 1,
  is        => 'rw',
  isa       => Str,
  predicate => 'has_log_format',
  writer    => 'set_log_format',
  trigger   => sub {
    my ($self, $val) = @_;
    $self->output->log_format($val) if $self->has_output;
  },
);


has 'output' => (
  lazy      => 1,
  is        => 'ro',
  isa       => sub {
    confess "Not a IRC::Server::Pluggable::Logger::Output subclass"
      unless blessed $_[0]
      and $_[0]->isa('IRC::Server::Pluggable::Logger::Output')
  },
  predicate => 'has_output',
  writer    => '_set_output',
  builder   => '_build_output',
);

sub _build_output {
  my ($self) = @_;

  my %opts;
  $opts{log_format}  = $self->log_format  if $self->has_log_format;
  $opts{time_format} = $self->time_format if $self->has_time_format;

  IRC::Server::Pluggable::Logger::Output->new(%opts)
}


has '_levmap' => (
  is      => 'ro',
  isa     => HashRef,
  default => sub {
    my $x;
    +{ (map {; $_ => ++$x } qw/error warn info debug/) }
  },
);


sub _should_log {
  my ($self, $level) = @_;

  $self->_levmap->{ $self->level } >= 
    ( $self->_levmap->{$level} // confess "unknown level $level" ) ? 
      1 : ()
}


sub log_to_level {
  my ($self, $level) = splice @_, 0, 2;

  $self->output->_write(
    $level,
    [ caller(1) ],
    @_
  ) if $self->_should_log($level);

  1
}


sub debug { shift->log_to_level( 'debug', @_ ) }
sub info  { shift->log_to_level( 'info',  @_ ) }
sub warn  { shift->log_to_level( 'warn',  @_ ) }
sub error { shift->log_to_level( 'error', @_ ) }

1;
__END__

=pod

=head1 NAME

IRC::Server::Pluggable::Logger

=head1 SYNOPSIS

  my $logger = IRC::Server::Pluggable::Logger->new(
    ## Required, one of: debug info warn error
    level => 'info',
  
    ## Optional, passed to Output class:
    time_format => "%Y/%m/%d %H:%M:%S"
    log_format  => "%time% %pkg% (%level%) %msg%"
  );

  ## Add outputs
  ## (See IRC::Server::Pluggable::Logger::Output for details)
  $logger->output->add(
    'Output::File' =>
      { file => $path_to_log },

    'Output::Term' =>
      { },
  );

  ## Log messages
  $logger->debug("Debugging message", @more_info );
  $logger->info("Informative message");
  $logger->warn("Warning message");
  $logger->error("Error message");

=head1 DESCRIPTION

Small/fast/flexible logging class.

Configured outputs must be added before log messages actually go 
anywhere (see the L</SYNOPSIS>). See L<IRC::Server::Pluggable::Logger::Output> for 
details.

=head2 Log Levels

A B<level> is required at construction-time; messages logged to the 
specified level or any level below it will be recorded.

For example, a B<level> of 'warn' will discard log messages to 'debug' 
and 'info' and report only 'warn' and 'error' messages.

Valid levels, from high to low:

  debug
  info
  warn
  error

These should be called as methods to log to the appropriate level:

  $logger->info("This is some information");

If a list is provided, it will be concatenated with an empty space 
between items:

  $logger->info("Some info", "more info");

=head2 Methods

=head3 set_level

Changes the current log level.

Call C<level> to retrieve the current log level.

=head3 set_time_format

Sets a date/time formatting string to be fed to C<strftime> -- see 
L<IRC::Server::Pluggable::Logger::Output>

Call C<time_format> to retrieve the current formatting string.

=head3 set_log_format

Sets a formatting template string for log messages -- see 
L<IRC::Server::Pluggable::Logger::Output>

Call C<log_format> to retrieve the current template string.

=head3 output

Returns the L<IRC::Server::Pluggable::Logger::Output> object.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
