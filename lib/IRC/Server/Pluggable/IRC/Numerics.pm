package IRC::Server::Pluggable::IRC::Numerics;

## Base class for numeric responses.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use Scalar::Util 'blessed';

use IRC::Server::Pluggable qw/
  IRC::Event
  Types
/;


use namespace::clean;


has 'rpl_map' => (
  lazy    => 1,
  is      => 'ro',
  isa     => HashRef,
  writer  => 'set_rpl_map',
  builder => '_build_rpl_map',
);

sub to_event {
  my $self = shift;
  my $hashified = $self->to_hash(@_);
  ev(%$hashified)
}

sub to_hash {
  ## ->to_hash(
  ##   $numeric,
  ##    prefix => $server,
  ##    target => $nick,
  ##    params => [ . . . ],
  ## );
  my ($self, $numeric) = splice @_, 0, 2;
  my %params = @_ > 1 ? @_ : %{$_[0]||{}};

  confess "to_hash() needs a numeric and a params hash with prefix/target"
    unless defined $params{prefix}
    and    defined $params{target};

  my $this_rpl = $self->rpl_map->{$numeric};
  confess "to_hash() called for unknown numeric $numeric"
    unless defined $this_rpl;

  my $target = $params{target};
  if (blessed $target 
    && $target->isa('IRC::Server::Pluggable::IRC::User') ) {
    $target = $target->nick
  }

  my %input = (
    command => $numeric,
    prefix  => $params{prefix},
    ## First specified param is always the target.
    params  => [ $target ],
  );

  my ($count, $string) = @$this_rpl;

  if ($count > 0) {
    ## Have prefix params; these come after the target.
    push @{$input{params}},
      splice @{$params{params}}, 0, $count;
  }

  if (index($string, '%') >= 0) {
    ## Have extra params.
    push @{$input{params}},
      sprintf($string, @{$params{params}})
  } else {
    push @{$input{params}}, $string
  }

  \%input
}

sub get_rpl {
  my ($self, $numeric) = @_;
  $self->rpl_map->{$numeric}
}

sub set_rpl {
  my ($self, $numeric, $ref) = @_;

  confess "set_rpl() expects a numeric and ARRAY"
    unless defined $numeric
    and ref $ref eq 'ARRAY';

  confess "ARRAY passed to set_rpl should have a param count and string"
    unless @$ref > 1;

  $self->rpl_map->{$numeric} = $ref
}

sub _build_rpl_map {
  my ($self) = @_;

  ## Based off the list in POE::Component::Server::IRC
  ## (Param specification concept also borrowed)

  {
    ## numeric => [ prefix_count , string ]

    401 => [ 1, "No such nick/channel" ],
    402 => [ 1, "No such server" ],
    403 => [ 1, "No such channel" ],
    404 => [ 1, "Cannot send to channel" ],
    405 => [ 1, "You have joined too many channels" ],
    406 => [ 1, "There was no such nickname" ],
    407 => [ 1, "Too many targets" ],
    408 => [ 1, "No such service" ],
    409 => [ 1, "No origin specified" ],
    411 => [ 0, "No recipient given (%s)" ],
    412 => [ 0, "No text to send" ],
    413 => [ 1, "No toplevel domain specified" ],
    414 => [ 1, "Wildcard in toplevel domain" ],
    415 => [ 1, "Bad server/host mask" ],
    421 => [ 1, "Unknown command" ],
    422 => [ 0, "MOTD File is missing" ],
    423 => [ 1, "No administrative info available" ],
    424 => [ 1, "File error doing %s on %s" ],
    431 => [ 1, "No nickname given" ],
    432 => [ 1, "Erroneous nickname" ],
    433 => [ 1, "Nickname is already in use" ],
    436 => [ 1, "Nickname collision KILL from %s\@%s" ],
    437 => [ 1, "Nick/channel is temporarily unavailable" ],
    441 => [ 1, "They aren't on that channel" ],
    442 => [ 1, "You're not on that channel" ],
    443 => [ 2, "is already on channel" ],
    444 => [ 1, "User not logged in" ],
    445 => [ 0, "SUMMON has been disabled" ],
    446 => [ 0, "USERS has been disabled" ],
    451 => [ 0, "You have not registered" ],
    461 => [ 1, "Not enough parameters" ],
    462 => [ 0, "You may not reregister" ],
    463 => [ 0, "Your host isn't among the privileged" ],
    464 => [ 0, "Password mismatch" ],
    465 => [ 0, "You are banned from this server" ],
    466 => [ 0, "You will be banned from this server" ],
    467 => [ 1, "Channel key already set" ],
    471 => [ 1, "Cannot join channel (+l)" ],
    472 => [ 1, "is unknown mode char to me for %s" ],
    473 => [ 1, "Cannot join channel (+i)" ],
    474 => [ 1, "Cannot join channel (+b)" ],
    475 => [ 1, "Cannot join channel (+k)" ],
    476 => [ 1, "Bad Channel Mask" ],
    477 => [ 1, "Channel doesn't support modes" ],
    478 => [ 2, "Channel list is full" ],
    481 => [ 0, "Permission Denied- You're not an IRC operator" ],
    482 => [ 1, "You're not channel operator" ],
    483 => [ 0, "You can't kill a server!" ],
    484 => [ 0, "Your connection is restricted!" ],
    485 => [ 0, "You're not the original channel operator" ],
    491 => [ 0, "No O-lines for your host" ],
    501 => [ 0, "Unknown MODE flag" ],
    502 => [ 0, "Cannot change mode for other users" ],
  }
}


no warnings 'void';
q{
 <Gilded> Has he done this before?
 <Gilded> Is vandalizing AT&T boxes his... calling?
 <Gilded> I'll show myself out.
};
