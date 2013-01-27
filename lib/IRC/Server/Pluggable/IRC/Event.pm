package IRC::Server::Pluggable::IRC::Event;

use strictures 1;

use Moo;
extends 'IRC::Message::Object';

use Exporter 'import';
our @EXPORT = 'ev';

sub ev {
  __PACKAGE__->new(@_)
}

1;

