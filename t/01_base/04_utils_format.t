use Test::More;
use strict; use warnings qw/FATAL all/;

use_ok('IRC::Server::Pluggable::Utils::Format');

cmp_ok(
  templatef( 'things %and% %stuff',
    and   => 'or',
    stuff => 'some objects',
  ),
  'eq',
  'things or some objects',
  'list-style templatef'
);

cmp_ok(
  templatef( 'things %or %objects',
    {
      or      => 'and perhaps',
      objects => 'some cake',
    },
  ),
  'eq',
  'things and perhaps some cake',
  'hashref templatef'
);

cmp_ok(
  templatef( 'string with %code',
    code => sub { "things" },
  ),
  'eq',
  'string with things',
  'coderef replacement'
);

done_testing;
