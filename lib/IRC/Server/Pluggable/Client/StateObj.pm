package IRC::Server::Pluggable::Client::StateObj;

use 5.12.1;
use Moo;
use Carp 'confess';

use IRC::Server::Pluggable qw/
  Types
  Utils
/;

use MooX::Struct -rw,
  Channel => [ qw/
    %present
  / ],

  User    => [ qw/
    nick
    user
    host
    realname
    +is_away
    +is_oper  
  / ],

  Topic   => [ qw/
    set_by!
    +set_at
    topic!
  / ],

  ISupport => [ qw/
    casemap!
  / ],
;


has 'nick_name'   => ();
has 'server_name' => ();

has '_users' => ();
has '_chans' => ();
has 'isupport_struct' => ();

sub casemap {
  my ($self) = @_;
  $self->isupport_struct->casemap || 'rfc1459'
}
with 'IRC::Server::Pluggable::Role::CaseMap';

sub get_channel {
  my ($self, $channel) = @_;
  confess "Expected a channel name" unless defined $channel;
  $self->_chans->{ $self->upper($channel) }
}

sub get_user {
  my ($self, $nick) = @_;
  confess "Expected a nickname" unless defined $nick;
  $self->_users->{ $self->upper($nick) }
}

sub get_status_prefix {
  my ($self, $channel, $nick) = @_;
  confess "Expected a channel and nickname"
    unless defined $channel and defined $nick;

  my $chan_obj = $self->_chans->{ $self->upper($channel) }
    || confess "Cannot locate channel struct for $channel";

  ## FIXME
}

sub get_isupport {
  my ($self, $key) = @_;
  confess "Expected a key" unless defined $key;
  return unless $self->isupport_struct->can($key);
  $self->isupport_struct->$key
}

1;

