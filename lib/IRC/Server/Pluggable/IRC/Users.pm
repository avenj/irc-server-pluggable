package IRC::Server::Pluggable::IRC::Users;

## Maintain a collection of User objects.

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Server::Pluggable qw/
  Types
/;


has 'casemap' => (
  required => 1,
  is  => 'ro',
  isa => CaseMap,
);

with 'IRC::Server::Pluggable::Role::CaseMap';


has '_users' => (
  ## Map (lowercased) nicknames to User objects.
  lazy => 1,
  is   => 'ro',
  isa  => HashRef,
  default => sub { {} },
);

sub add {
  my ($self, $user) = @_;

  confess "$user is not a IRC::Server::Pluggable::IRC::User"
    unless is_Object($user)
    and $user->isa('IRC::Server::Pluggable::IRC::User');

  my $nick = $self->lower( $user->nick );

  $self->_users->{$nick} = $user;

  $user
}

sub as_array {
  my ($self) = @_;

  [ map { $self->_users->{$_}->nick } keys %{ $self->_users } ]
}

sub by_nick {
  my ($self, $nick) = @_;

  unless (defined $nick) {
    carp "by_nick() called with no nickname specified";
    return
  }

  $self->_users->{ $self->lower($nick) }
}

sub del {
  my ($self, $nick) = @_;

  confess "del() called with no nickname specified"
    unless defined $nick;

  $nick = $self->lower($nick);

  delete $self->_users->{$nick}
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
  my $this_user = $users->by_nick( $nickname );

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

=head3 by_nick

  my $user = $users->by_nick( $nickname );

Returns the L<IRC::Server::Pluggable::IRC::User> (sub)class instance for 
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
