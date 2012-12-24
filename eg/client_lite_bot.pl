#!/usr/bin/env perl
use strictures 1;

my $nickname = 'litebot';
my $username = 'clientlite';
my $server   = 'irc.cobaltirc.org';
my @channels = ( '#otw', '#unix' );

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
    server   => $server,
    nick     => $nickname,
    username => $username,
  )->connect();
}

sub E_irc_001 {
  my ($kern, $heap, $ev) = @_[KERNEL, HEAP, ARG0];

  ## Chainable methods.
  my $irc = $heap->{irc};
  $irc->join(@channels)->privmsg(join(',', @channels), "hello!");
}

sub E_irc_public_msg {
  my ($kern, $heap, $ev) = @_[KERNEL, HEAP, ARG0];
  my ($target, $string)  = @{ $ev->params };

  if (lc($string || '') eq 'hello') {
    $heap->{irc}->privmsg($target, "hello, world!");
  }
}

sub E_irc_ctcp_version {
  my ($kern, $heap, $ev) = @_[KERNEL, HEAP, ARG0];

  my $from = parse_user( $ev->prefix );

  $heap->{irc}->notice( $from,
    ctcp_quote("VERSION a silly Client::Lite example"),
  );
}

