#!/usr/bin/env perl

use strictures 1;
use POE;

use Data::Dumper;

use IRC::Server::Pluggable qw/
  Client::Lite
  Utils
  Utils::Parse::CTCP
/;

POE::Session->create(
  package_states => [
    main => [ qw/
      _start
      E_irc_public_msg
      E_irc_ctcp_version
      E_irc_001
    / ],
  ],
);
$poe_kernel->run;

sub _start {
  my ($kern, $heap) = @_[KERNEL, HEAP];
  $heap->{irc} = prefixed_new( 'Client::Lite' =>
    event_prefix => 'E_',
    server => 'irc.cobaltirc.org',
    nick   => 'litebot',
    username => 'clientlite',
  );
  $heap->{irc}->connect;
}

sub E_irc_001 {
  my ($kern, $heap, $ev) = @_[KERNEL, HEAP, ARG0];
  $heap->{irc}->join('#otw','#unix');
}

sub E_irc_public_msg {
  my ($kern, $heap, $ev) = @_[KERNEL, HEAP, ARG0];
  print Dumper $ev;
  if (lc($ev->params->[1] || '') eq 'hello') {
    $heap->{irc}->privmsg($ev->params->[0], "hello, world!");
  }
}

sub E_irc_ctcp_version {
  my ($kern, $heap, $ev) = @_[KERNEL, HEAP, ARG0];
  my $from = parse_user( $ev->prefix );
  $heap->{irc}->notice( $from,
    ctcp_quote("VERSION a silly Client::Lite example"),
  );
}

