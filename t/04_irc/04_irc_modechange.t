use Test::More;
use strict; use warnings FATAL => 'all';

my $class = 'IRC::Server::Pluggable::IRC::ModeChange';


use_ok( $class );

my $from_string = new_ok( $class =>
  [
    mode_string => '+o-o+v avenj Joah Gilded',
  ],
);

my $array = $from_string->mode_array;
is_deeply( $array,
  [
    [ '+', 'o', 'avenj' ],
    [ '-', 'o', 'Joah'  ],
    [ '+', 'v', 'Gilded' ],
  ],
) or diag explain $array;

is_deeply( $from_string->next, 
  [ '+', 'o', 'avenj' ], 
  'next(1) mode looks ok'
);
is_deeply( $from_string->next,
  [ '-', 'o', 'Joah' ],
  'next(2) mode looks ok'
);
is_deeply( $from_string->reset->next,
  [ '+', 'o', 'avenj' ],
  'reset looks ok'
);
$from_string->reset;

my $from_array = new_ok( $class =>
  [
    mode_array => $array,
  ],
);
cmp_ok( $from_array->mode_string, 'eq', '+o-o+v avenj Joah Gilded' );

my $long = new_ok( $class =>
  [
    mode_string => '+o-o+o-o+vb avenj avenj Joah Joah Gilded some@mask'
  ],
);

is_deeply( $long->mode_array,
  [
    [ '+', 'o', 'avenj' ],
    [ '-', 'o', 'avenj' ],
    [ '+', 'o', 'Joah'  ],
    [ '-', 'o', 'Joah'  ],
    [ '+', 'v', 'Gilded' ],
    [ '+', 'b', 'some@mask' ],
  ],
) or diag explain $long->mode_array;

my @splitm = $long->split_mode_set(3);
cmp_ok(@splitm, '==', 2, 'split_mode_set spawned 2 sets' )
  or diag explain \@splitm;

cmp_ok($splitm[0]->mode_string, 'eq', '+o-o+o avenj avenj Joah' );
cmp_ok($splitm[1]->mode_string, 'eq', '-o+vb Joah Gilded some@mask' );

my $from_match = $long->from_matching('v');
isa_ok($from_match, $class, 'from_matching returned obj' );
cmp_ok($from_match->mode_string, 'eq', '+v Gilded', 
  'from_matching mode_string looks ok'
);

done_testing;
