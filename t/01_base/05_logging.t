use Test::More;
use strict; use warnings FATAL => 'all';

use_ok($_) for map { 'IRC::Server::Pluggable::'.$_ } qw/
  Logger::Output::File
  Logger::Output::Term
  Logger::Output
  Logger
/;

## FIXME use File::Temp instead?
my $test_log_path = "ispluggablet.log";

my $file_out = new_ok( 'IRC::Server::Pluggable::Logger::Output::File' =>
  [ file => $test_log_path ]
);

cmp_ok( $file_out->file, '=~', qr/ispluggablet\.log$/ );
is( $file_out->perms, 0666, 'perms() returned 0666' );

ok( $file_out->_write("Test string"), 'write_()' );
ok( -e $test_log_path, 'Log file exists' );
my $contents = do {
  open my $fh, '<', $test_log_path or die $!;
  local $/; <$fh>
};
chomp $contents;
cmp_ok($contents, 'eq', 'Test string', 'Log contents look OK' );

undef $contents;
unlink $test_log_path if -f $test_log_path;


my $term_out = new_ok( 'IRC::Server::Pluggable::Logger::Output::Term' );

my $stdout;
{
  local *STDOUT;
  open *STDOUT, '>', \$stdout or die "stdout reopen: $!";
  $term_out->_write("Test string");
  close *STDOUT
}

cmp_ok( $stdout, 'eq', 'Test string', 'STDOUT log looks ok' );


my $output = new_ok( 'IRC::Server::Pluggable::Logger::Output' );
ok( $output->time_format, 'has time_format' );
ok( $output->log_format, 'has log_format' );

ok(
  $output->add(
    myfile => { type => 'File', file => $test_log_path },
    myterm => { type => 'Term' },
  ),
  'add() file and term outputs'
);

undef $stdout;
{
  local *STDOUT;
  open *STDOUT, '>', \$stdout or die "stdout reopen: $!";
  $output->_write('info', [caller(0)], 'Testing', 'things');
  close *STDOUT
}

ok( $stdout, 'Logged to STDOUT' );
$contents = do {
  open my $fh, '<', $test_log_path or die $!;
  local $/; <$fh>
};
chomp $contents;
ok( length $contents, 'Logged to file' );

undef $contents;
unlink $test_log_path if -f $test_log_path;

isa_ok( $output->get('myterm'),
  'IRC::Server::Pluggable::Logger::Output::Term',
  'get() returned object'
);

cmp_ok( $output->del('myterm', 'myfile'), '==', 2, 'del() 2 objects' );
ok(!$output->get('myterm'), 'objects were deleted');

my $logobj = new_ok( 'IRC::Server::Pluggable::Logger' => [
    level => 'info',
  ]
);

ok(!$logobj->_should_log('debug'), 'should not log debug()' );
ok( $logobj->_should_log('info'), 'should log info()' );
ok( $logobj->_should_log('warn'), 'should log warn()' );
ok( $logobj->set_level('warn'), 'set_level warn' );
is( $logobj->level, 'warn', 'level was reset' );
ok(!$logobj->_should_log('info'), 'should not log info()' );

isa_ok( $logobj->output, 'IRC::Server::Pluggable::Logger::Output' );
ok(
  $logobj->output->add(
    myfile => { type => 'File', file => $test_log_path },
  ),
  'output->add()'
);

$logobj->set_level('debug');
$logobj->$_("Testing $_") for qw/debug info warn error/;

my @contents = do {
  open my $fh, '<', $test_log_path or die $!;
  readline($fh)
};
cmp_ok( @contents, '==', 4, 'expected line count in log' );

unlink $test_log_path if -f $test_log_path;

done_testing;
