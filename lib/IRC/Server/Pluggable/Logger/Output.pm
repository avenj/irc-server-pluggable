package IRC::Server::Pluggable::Logger::Output;
use 5.12.1;
use strictures 1;

## Torn wholesale from Bot::Cobalt::Logger::*

use Carp;
use Moo;

use IRC::Server::Pluggable qw/
  Utils::Format
  Types
/;

use POSIX ();
use Try::Tiny;


use namespace::clean;


has 'time_format' => (
  ## Fed to POSIX::strftime()
  is      => 'ro',
  isa     => Str,
  writer  => 'set_time_format',
  default => sub {
    "%Y-%m-%d %H:%M:%S"
  },
);

has 'log_format' => (
  ## Fed to Utils::Format::templatef()
  is      => 'ro',
  isa     => Str,
  writer  => 'set_log_format',
  default => sub {
    "%level %time (%pkg%) %msg"
  },
);


has '_outputs' => (
  is      => 'rwp',
  isa     => HashRef,  
  default => sub { {} },
);


sub add {
  my ($self, @args) = @_;
  
  unless (@args && @args % 2 == 0) {
    confess "add() expects an even number of arguments, ",
         "mapping an Output class to constructor arguments"
  }
  
  my $prefix = 'IRC::Server::Pluggable::Logger::Output::' ;
  
  CONFIG: while (my ($alias, $opts) = splice @args, 0, 2) {
    confess "Can't add $alias, opts are not a HASH"
      unless ref $opts eq 'HASH';

    confess "Can't add $alias, no type specified"
      unless $opts->{type};

    my $target_pkg = $prefix . delete $opts->{type};

    { local $@;
      eval "require $target_pkg";
      
      if (my $err = $@) {
        carp "Could not add logger $alias: $err";
        next CONFIG
      }
    }

    my $new_obj = try {
      $target_pkg->new(%$opts)
    } catch {
      carp "Could not add logger $alias; new() died: $_";
      undef
    } or next CONFIG;

    $self->_outputs->{$alias} = $new_obj;
  }  ## CONFIG

  1
}

sub del {
  my ($self, @aliases) = @_;
  my @deleted;
  for my $alias (@aliases) {
    if (my $item = delete $self->_outputs->{$alias}) {
      push @deleted, $item
    }
  }

  @deleted
}

sub get {
  my ($self, $alias) = @_;
  $self->_outputs->{$alias}
}



sub _format {
  my ($self, $level, $caller, @strings) = @_;
  
  templatef( $self->log_format, {
    level => $level,

    ## Actual message.
    msg  => join(' ', @strings),  

    time => POSIX::strftime( $self->time_format, localtime ),

    ## Caller details, split out.
    pkg  => $caller->[0],
    file => $caller->[1],
    line => $caller->[2],
    sub  => $caller->[3],
  }) . "\n"
}

sub _write {
  my $self = shift;

  my $formatted = $self->_format(@_);
  while (my ($alias, $output) = each %{ $self->_outputs }) {
    $output->_write(
      ## Output classes can provide their own _format
      $output->can('_format') ?  $output->_format( @_ )
        : $formatted
    )
  }

  1
}

1;
__END__

=pod

=head1 NAME

IRC::Server::Pluggable::Logger::Output - Log handler output manager

=head1 SYNOPSIS

  ## Normally constructed by IRC::Server::Pluggable::Logger

  my $log_output = IRC::Server::Pluggable::Logger::Output->new(
    log_format  => $log_format,
    time_format => $time_format,
  );
  
  $log_output->add(
    'my_alias' => {
      type => 'File',
      file => $path_to_log,
    },
  );

=head1 DESCRIPTION

This is the output manager for L<IRC::Server::Pluggable::Logger>, handling
dispatch to log writers such as
L<IRC::Server::Pluggable::Logger::Output::File> and
L<IRC::Server::Pluggable::Logger::Output::Term>.

=head2 Methods

=head3 add

C<add()> takes a list of aliases to add, mapped to a HASH containing the 
name of their writer class (B<type>) and arguments to pass to the writer 
class constructor:

  $log_output->add(
    ## Add a IRC::Server::Pluggable::Logger::Output::File
    ## new() is passed 'file => $path_to_log'
    MyLogger => {
      type => 'File',
      file => $path_to_log,
    },
    
    ## Add a Logger::Output::Term also:
    Screen => {
      type => 'Term',
    },
  );

The specified outputs will be initialized and tracked; their C<_write> 
method is called when log messages are received.

=head3 del

C<del()> takes a list of aliases to delete.

Returns the number of aliases actually deleted.

=head3 get

C<get()> takes an alias and returns the appropriate writer object (or 
undef).

=head3 log_format

B<log_format> can be specified at construction time or changed on the 
fly.

This is used to specify the actual layout of each individual logged 
message (for the default formatter; specific output classes may choose 
to override the formatter and disregard log_format).

Takes a L<IRC::Server::Pluggable::Tools::Format/templatef> template string; 
normal templatef usage rules apply -- a replacement sequence starts with '%' 
and is terminated by either a space or a trailing '%'.

Defaults to "%level %time (%pkg%) %msg"

Replacement variables passed in to the template are:

  msg     Actual (concatenated) log message
  level   Level this message was logged to
  time    Current date and time (see time_format)
  pkg     Package this log method was called from
  file    File called from
  line    Line called from
  sub     Subroutine called from

=head3 time_format

B<time_format> can be specified at construction time or changed on the 
fly.

This is used to create the '%time' template variable for L</log_format>.

It is fed to C<strftime> to create a time/date string; see the 
documentation for C<strftime> on your system for a complete list of 
usable replacement sequences.

Defaults to "%Y-%m-%d %H:%M:%S"

Commonly used replacement sequences include:

  %Y   Current year including century.  
  %m   Current month (as a number)
  %d   Current day of the month.

  %A   Full weekday name
  %a   Abbreviated weekday name
  %B   Full month name
  %b   Abbreviated month name

  %H   Hour of the day (on a 24-hour clock)
  %I   Hour of the day (on a 12-hour clock)
  %p   'AM' or 'PM' indication
  %M   Current minute
  %S   Current second
  %Z   Current timezone

  %s   Seconds since epoch ("Unix time")
    
  %%   Literal %

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
