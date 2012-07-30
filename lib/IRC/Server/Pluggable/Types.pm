package IRC::Server::Pluggable::Types;

use strictures 1;
use base 'Exporter';

use MooX::Types::MooseLike::Base;

our @EXPORT = $MooX::Types::MooseLike::Base::EXPORT_OK;

sub import {
  __PACKAGE__->export_to_level(1, @_)
}

1;
