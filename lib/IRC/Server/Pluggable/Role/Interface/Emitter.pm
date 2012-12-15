package IRC::Server::Pluggable::Role::Interface::Emitter;
use strictures 1;
use Moo::Role;

requires qw/
  emit
  emit_now
  process
/;

1;
