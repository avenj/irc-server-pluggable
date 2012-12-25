package IRC::Server::Pluggable::Role::Interface::Client;
use strictures 1;
use Moo::Role;

requires 
  ## Attributes
  qw/
    nick
    server
    username
    realname
  /,

  ## Fundamentals
  qw/
    connect
    disconnect
    send
  /,

  ## IRC
  qw/
    privmsg
    notice
    ctcp

    mode
    join
    part
  /,
;

1;

=pod

=head1 NAME

IRC::Server::Pluggable::Role::Interface::Client

=head1 SYNOPSIS

  use Moo;
  with 'IRC::Server::Pluggable::Role::Interface::Client';

=head1 DESCRIPTION

An abstract Role defining an interface to an IRC client, such as
L<IRC::Server::Pluggable::Client::Lite>.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
