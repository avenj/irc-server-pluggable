package IRC::Server::Pluggable::IRC::Users;

## Maintain a collection of User objects.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use Scalar::Util 'weaken';

use IRC::Server::Pluggable qw/
  Types
  Utils::TS::ID
/;

use IRC::Toolkit::Masks;

use namespace::clean;


has casemap => (
  required => 1,
  is       => 'ro',
  isa      => CaseMap,
);

with 'IRC::Toolkit::Role::CaseMap';

has _users => (
  ## Map (lowercased) nicknames to User objects.
  lazy => 1,
  is   => 'ro',
  default => sub { {} },
);

has _by_uid => (
  lazy => 1,
  is   => 'ro',
  default => sub { {} },
);

has _by_wheelid => (
  lazy => 1,
  is   => 'ro',
  default => sub { {} },
);

has _uniq_id => (
  lazy => 1,
  is   => 'ro',
  default => sub { ts6_id },
);

sub next_unique_id {
  my ($self) = @_;
  $self->_uniq_id->next
}


sub add {
  my ($self, $user) = @_;

  confess "$user is not a IRC::Server::Pluggable::IRC::User"
    unless is_Object($user)
    and $user->isa('IRC::Server::Pluggable::IRC::User');

  my $nick = $self->lower( $user->nick );

  $self->_users->{$nick} = $user;
  $self->_by_uid->{ $user->uid } = $user;
  weaken $self->_by_uid->{ $user->uid };

  if ($user->has_conn) {
    ## Local user. Map their route ID to a weakened User ref.
    $self->_by_wheelid->{ $user->conn->wheel_id } = $user;
    weaken $self->_by_wheelid->{ $user->conn->wheel_id };
  }

  $user
}

sub as_array {
  my ($self) = @_;
  values %{ $self->_users }
}

sub nicknames_as_array {
  my ($self) = @_;
  [ map { $self->_users->{$_}->nick } keys %{ $self->_users } ]
}

sub by_name {
  my ($self, $nick) = @_;

  unless (defined $nick) {
    confess "by_name() called with no nickname specified";
    return
  }

  $self->_users->{ $self->lower($nick) }
}

sub by_id {
  my ($self, $id) = @_;

  unless (defined $id) {
    confess "by_id() called with no ID specified";
    return
  }

  $self->_by_wheelid->{$id}
}

sub by_uid {
  my ($self, $uid) = @_;

  unless (defined $uid) {
    confess "by_uid() called with no UID specified";
    return
  }

  $self->_by_uid->{$uid}
}

sub del {
  my ($self, $nick) = @_;

  confess "del() called with no nickname specified"
    unless defined $nick;

  $nick = $self->lower($nick);

  if (my $user = delete $self->_users->{$nick}) {
    delete $self->_by_uid->{ $user->uid };
    delete $self->_by_wheelid->{ $user->conn->wheel_id }
      if $user->has_conn;
    return $user
  }
}

sub matching {
  my ($self, $mask) = @_;

  ## Note that this currently returns the IRC-lowercase version.

  confess "matching() called with no mask specified"
    unless defined $mask;

  my @matches;
  my $casemap = $self->casemap;
  for my $nick (keys %{ $self->_users }) {
    my $user = $self->_users->{$nick};
    push @matches, $user
      if matches_mask( $mask, $nick, $casemap )
  }

  wantarray ? @matches : @matches ? \@matches : ()
}

sub nuh_matching {
  my ($self, $mask) = @_;

  confess "nuh_matching() called with no mask specified"
    unless defined $mask;

  my @matches;
  my $casemap = $self->casemap;
  for my $nick (keys %{ $self->_users }) {
    my $user = $self->_users->{$nick};
    my $nuh  = $user->full;
    push @matches, $user
      if matches_mask( $mask, $nuh, $casemap )
  }

  wantarray ? @matches : @matches ? \@matches : ()
}

1;

=pod

=head1 NAME

IRC::Server::Pluggable::IRC::Users - Base class for User object tracking

=head1 SYNOPSIS

  ## Create a User tracker
  my $users = IRC::Server::Pluggable::IRC::Users->new(
    casemap => $protocol_obj->casemap,
  );

  ## Add User objects
  $users->add(
    IRC::Server::Pluggable::IRC::User->new(
     . . .
    );
  );

  ## Retrieve specified nickname's object
  my $this_user = $users->by_name( $nickname );

  ## Delete specified nickname's object
  $users->del( $nickname );

  ## Retrieve all nicknames in state
  my $array = $users->as_array;

=head1 DESCRIPTION

L<IRC::Server::Pluggable::Protocol> classes can use this to manage a 
collection of L<IRC::Server::Pluggable::IRC::User> (or subclasses 
thereof) objects.

An appropriate casemap should be specified at construction time:

  my $users = IRC::Server::Pluggable::IRC::Users->new(
    casemap => $protocol->casemap,
  );

=head2 Attributes

=head3 casemap

The configured casemap; used to handle nicknames properly. See 
L<IRC::Server::Pluggable::Utils/"lc_irc"> for details on IRC casemap 
rules.

=head2 Methods

=head3 as_array

Returns the current list of nicknames as an array reference.

=head3 by_id

  my $user = $users->by_id( $conn->wheel_id );

Returns the L<IRC::Server::Pluggable::IRC::User> object belonging to a 
local user with the specified route/wheel ID. Also see L</by_name>

=head3 by_name

  my $user = $users->by_name( $nickname );

Returns the L<IRC::Server::Pluggable::IRC::User> object instance for 
the specified nickname. Returns false if the nickname is not known.

Nickname does not need to be case-munged; this class will handle that for 
you.

=head3 add

  $users->add( $user_obj );

Adds the specified L<IRC::Server::Pluggable::IRC::User> (sub)class 
instance.

Replaces an existing entry if $user_obj->nick is the same (per specified 
casemap rules).

Returns the User object on success.

=head3 del

  $users->del( $nickname );

Deletes the specified nickname's User object.

Returns the User object on success, boolean false on failure.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
