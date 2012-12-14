use Test::More tests => 17;
use strict; use warnings FATAL => 'all' ;

BEGIN {
  use_ok( 'IRC::Server::Pluggable::Backend' );
  use_ok( 'IRC::Server::Pluggable::IRC::Event' );
}

my $backend = IRC::Server::Pluggable::Backend->new;
my $filter = $backend->filter;

my $raw_line = ":server.org 001 user :Welcome to IRC\r\n";
my $arr = $filter->get([$raw_line]);
my $hash = shift @$arr;

my $obj = new_ok( 'IRC::Server::Pluggable::IRC::Event' => [
    %$hash
  ],
);

cmp_ok( $obj->prefix, 'eq', 'server.org', 'prefix looks ok' );
cmp_ok( $obj->command, 'eq', '001', 'command looks ok' );
cmp_ok( $obj->params->[0], 'eq', 'user', 'param 0 looks ok' );
cmp_ok( $obj->params->[1], 'eq', 'Welcome to IRC', 'param 1 looks ok' );

my $short = ev(%$hash);
isa_ok($short, 'IRC::Server::Pluggable::IRC::Event', 'ev() produced obj' );
cmp_ok( $short->command, 'eq', '001', 'ev()->command() looks ok' );

my $tag_line = q{@intent=ACTION;znc.in/extension=value;foobar}
            . qq{ PRIVMSG #somewhere :Some string\r\n};
my $parsed = $filter->get([$tag_line])->[0];
my $tagged = IRC::Server::Pluggable::IRC::Event->new(%$parsed);

$tag_line =~ s/\r\n//;

cmp_ok( $tagged->raw_line, 'eq', $tag_line, 'raw_line looks ok' );

ok( $tagged->has_tags, 'has_tags looks ok' );
is_deeply( $tagged->tags,
  +{
    foobar => undef,
    intent => 'ACTION',
    'znc.in/extension' => 'value',
  },
  'tags looks ok'
);
cmp_ok( $tagged->get_tag('intent'), 'eq', 'ACTION', 'get_tag looks ok' );

ok(
  $tagged->tags_as_string =~ qr/intent=ACTION(?:[;\s]|$)/ &&
  $tagged->tags_as_string =~ qr/znc\.in\/extension=value(?:[;\s]|$)/ &&
  $tagged->tags_as_string =~ qr/foobar(?:[;\s]|$)/,
  'tags_as_string'
) or diag "Got string ".$tagged->tags_as_string;

ok(
  (grep {; $_ eq 'foobar' } @{ $tagged->tags_as_array }) &&
  (grep {; $_ eq 'znc.in/extension=value' } @{ $tagged->tags_as_array }) &&
  (grep {; $_ eq 'intent=ACTION' } @{ $tagged->tags_as_array }),
  'tags_as_array looks ok'
) or diag explain $tagged->tags_as_array;

my $from_raw = new_ok( 'IRC::Server::Pluggable::IRC::Event' => [
    raw_line => $tag_line,
  ],
);
cmp_ok( $from_raw->command, 'eq', 'PRIVMSG', 'obj from raw_line looks ok' );
