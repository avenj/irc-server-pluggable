package IRC::Server::Pluggable::Client::Stateful;

use 5.12.1;
use Moo;
use POE;
use Carp 'confess';

extends 'IRC::Server::Pluggable::Client::Lite';

## FIXME add known user state
## FIXME move the State struct to a real class,
##  consume all the MooX::Struct bits from there?

use MooX::Struct -rw,
  State => [ 
    qw/
      %channels
      $isupport_struct
      nick_name
      server_name
    /,
    ## Abuse MooX::Struct a bit to get easy uc_irc():
    get_channel => sub {
      my ($self, $channel) = @_;
      confess "Expected a channel name" unless defined $channel;
      my $casemap = $self->get_isupport('casemap');
      $channel = uc_irc($channel, $casemap);
      $self->channels->{$channel}
    },
    get_status_prefix => sub {
      my ($self, $channel, $nick) = @_;
      confess "Expected a channel and nickname"
        unless defined $channel and defined $nick;
      my $casemap = $self->get_isupport('casemap');
      ($channel, $nick) = map {; uc_irc($_, $casemap) } ($channel, $nick);
      $self->channels->{$channel}->nicknames->{$nick}
    },
    get_isupport => sub {
      my ($self, $key) = @_;
      confess "Expected a key" unless defined $key;
      return unless $self->isupport_struct->can($key);
      $self->isupport_struct->$key
    },
  ],

  Channel => [ qw/
      %nicknames
      $topic
  / ],

  Topic => [ qw/
    set_by!
    +set_at
    topic!
  / ],

  ISupport => [ qw/
    casemap!
  / ],
;

## Factory method for subclasses.
sub _create_struct {
  my ($self, $type) = splice @_, 0, 2;
  my $obj;
  for (lc $type) {
    $obj = Channel->new(@_)  when 'channel';
    $obj = ISupport->new(@_) when 'isupport';
    $obj = State->new(@_)    when 'state';
    $obj = Topic->new(@_)    when 'topic';
    confess "cannot create struct - unknown type $type"
  }
  $obj
}

use MooX::Role::Pluggable::Constants;
use IRC::Server::Pluggable qw/
  IRC::Event
  Utils
  Types
/;

with 'IRC::Server::Pluggable::Role::Interface::Client';


has state => (
  lazy    => 1,
  is      => 'ro',
  isa     => Object,
  clearer => '_clear_state',
  writer  => '_set_state',
  builder => '_build_state',
);

sub _build_state { 
    State->new(
      channels    => {},
      nick_name   => '',
      server_name => '',
      isupport_struct => ISupport->new( casemap => 'rfc1459' ),
    )
}


### Overrides.
around ircsock_disconnect => sub {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $str) = @_[ARG0, ARG1];
  
  $self->_clear_conn if $self->_has_conn;
  
  my $connected_to = $self->state->server_name;
  $self->_set_state( $self->_build_state );
  
  $self->emit( 'irc_disconnected', $str, $connected_to );
};



### Our handlers.

sub N_irc_001 {
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };

  $self->state->server_name( $ircev->prefix );

  $self->state->nick_name(
    (split ' ', $ircev->raw_line)[2]
  );

  EAT_NONE
}

sub N_irc_005 {
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };

  my %isupport;
  my @params = @{ $ircev->params };
  ## Drop target nickname, trailing 'are supported by ..':
  shift @params;
  pop   @params;

  for my $item (@params) {
    my ($key, $val) = split /=/, $item, 2;
    $key = lc $key;
    if (defined $val) {
      $isupport{$key} = $val
    } else {
      $isupport{$key} = -1;
    }
  }

  for my $key (keys %isupport) {
    $self->state->isupport_struct->EXTEND(
      -rw => $key
    ) unless $self->state->isupport_struct->can($key);
    $self->state->isupport_struct->$key( $isupport{$key} )
  }

  EAT_NONE
}

sub N_irc_332 {
  ## Topic
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };

  my (undef, $target, $topic) = @{ $ircev->params };

  my $casemap = $self->state->get_isupport('casemap');
  $target     = uc_irc( $target, $casemap );

  my $chan_obj = $self->state->channels->{$target};
  $chan_obj->topic->topic( $topic );

  EAT_NONE
}

sub N_irc_333 {
  ## Topic setter & TS
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };
  my (undef, $target, $setter, $ts) = @{ $ircev->params };
 
  my $casemap = $self->state->get_isupport('casemap');
  $target     = uc_irc( $target, $casemap );

  my $chan_obj = $self->state->channels->{$target};
  $chan_obj->topic->set_at( $ts );
  $chan_obj->topic->set_by( $setter );

  EAT_NONE
}

sub N_irc_352 {
  ## WHO reply
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };

  ## We only parse a small chunk.
  ## The rest of the params are documented here for convenience.
  my (
    undef,      ## Target (us)
    $target,    ## Channel
    undef,      ## Username
    undef,      ## Hostname
    undef,      ## Servername
    $nick, 
    $status, 
    undef       ## Hops + Realname
  ) = @{ $ircev->params };

  my $casemap = $self->state->get_isupport('casemap');
  $target     = uc_irc( $target, $casemap ); 
  $nick       = uc_irc( $nick,   $casemap );

  my $chan_obj = $self->state->channels->{$target};
  
  ##  FIXME update nickname(s) for applicable channel(s)
  ##   add status prefixes

  EAT_NONE
 }

sub N_irc_nick {
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };
  ## FIXME update our nick as-needed
  ##  Update our channels as-needed
  EAT_NONE
}

sub N_irc_mode {
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };
  my ($target, $modestr, @params) = @{ $ircev->params };

  my $casemap  = $self->state->get_isupport('casemap');
  $target      = uc_irc( $target, $casemap );
  my $chan_obj = $self->state->channels->{$target} || return EAT_NONE;

  my(@always, @whenset);
  if (my $cmodes = $self->state->get_isupport('chanmodes')) {
    my ($list, $always, $whenset) = split /,/, $cmodes;
    push @always,  split('', $list), split('', $always);
    push @whenset, split '', $whenset;
  }

  my %prefixes = (
    'o' => '@',
    'h' => '%',
    'v' => '+',
  );

  PREFIX: {
    if (my $sup_prefix = $self->state->get_isupport('prefix')) {
      my (undef, $modes, $symbols) = split /[\()]/, $sup_prefix;
      last PREFIX unless $modes and $symbols
        and length $modes == length $symbols;
      $modes   = [ split '', $modes ];
      $symbols = [ split '', $symbols ];
      @prefixes{@$modes} = @$symbols
    }
  }

  my $mode_hash = mode_to_hash( $modestr,
    params       => [ @params ],
    ( @always   ? (param_always => \@always)  : () ),
    ( @whenset  ? (param_set    => \@whenset) : () ),
  );
 
  MODE_ADD: for my $char (keys %{ $mode_hash->{add} }) {
    next MODE_ADD unless exists $prefixes{$char}
      and ref $mode_hash->{add}->{$char} eq 'ARRAY';
    my $param = $mode_hash->{add}->{$char}->[0];
    my $this_user;
    unless ($this_user = $chan_obj->nicknames->{ uc_irc($param, $casemap) }) {
      warn "Mode change for nonexistant user $param";
      next MODE_ADD
    }
    push @$this_user, $prefixes{$char}
  }

  MODE_DEL: for my $char (keys %{ $mode_hash->{del} }) {
    next MODE_DEL unless exists $prefixes{$char}
      and ref $mode_hash->{del}->{$char} eq 'ARRAY';
    my $param = $mode_hash->{del}->{$char}->[0];
    my $this_user;
    unless ($this_user = $chan_obj->nicknames->{ uc_irc($param, $casemap) }) {
      warn "Mode change for nonexistant user $param";
      next MODE_DEL
    }
    @$this_user = grep {; $_ ne $prefixes{$char} } @$this_user
  }

  EAT_NONE
}

sub N_irc_join {
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };

  my ($nick, $user, $host) = parse_user( $ircev->prefix );

  my $casemap = $self->state->get_isupport('casemap');
  my $target  = uc_irc( $ircev->params->[0], $casemap );
  $nick       = uc_irc( $nick, $casemap );

  if ( eq_irc($nick, $self->state->nick_name, $casemap) ) {
    ## Us. Add new Channel struct.
    $self->state->channels->{$target} = Channel->new(
      nicknames => {},
      topic     => Topic->new(
        set_by => '',
        set_at => 0,
        topic  => '',
      ),
    );
    ## ... and request a WHO
    $self->send(
      ev(
        command => 'who',
        params  => [ $ircev->params->[0] ],
      )
    );
  }

  my $chan_obj = $self->state->channels->{$target};
  $chan_obj->nicknames->{$nick} = [];

  EAT_NONE
}

sub N_irc_part {
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };
  
  my ($nick)  = parse_user( $ircev->prefix );
  my $casemap = $self->state->get_isupport('casemap');
  my $target  = uc_irc( $ircev->params->[0], $casemap );
  $nick       = uc_irc( $nick, $casemap );
  
  delete $self->state->channels->{$target};
  
  EAT_NONE
}

sub N_irc_quit {
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };

  my ($nick)  = parse_user( $ircev->prefix );
  my $casemap = $self->state->get_isupport('casemap');
  $nick       = uc_irc( $nick, $casemap );

  while (my ($channel, $chan_obj) = each %{ $self->state->channels }) {
    delete $chan_obj->nicknames->{$nick};
  }

  EAT_NONE
}

sub N_irc_topic {
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };
  
  my ($nick, $user, $host) = parse_user( $ircev->prefix );
  my ($target, $str) = @{ $ircev->params };

  my $casemap = $self->state->get_isupport('casemap');
  $target     = uc_irc( $target, $casemap );
 
  my $chan_obj = $self->state->channels->{$target};
  $chan_obj->topic( Topic->new(
      set_at => time(),
      set_by => $ircev->prefix,
      topic  => $str,
    )
  );

  EAT_NONE
}



1;


__END__

=pod

=head1 NAME

IRC::Server::Pluggable::Client::Stateful - Stateful Client::Lite subclass

=head1 SYNOPSIS

=head1 DESCRIPTION

This is a state-tracking subclass of L<IRC::Server::Pluggable::Client::Lite>.

FIXME this is the POD as extracted from Lite:


=head2 State

The State struct provides some very basic state information that can be
queried via accessor methods:

=head3 nick_name

  my $current_nick = $irc->state->nick_name;

Returns the client's current nickname.

=head3 server_name

  my $current_serv = $irc->state->server_name;

Returns the server's announced name.

=head3 get_isupport

  my $casemap = $irc->state->get_isupport('casemap');

Returns ISUPPORT values, if they are available.

If the value is a KEY=VALUE pair (e.g. 'MAXMODES=4'), the VALUE portion is
returned.

A value that is a simple boolean (e.g. 'CALLERID') will return '-1'.

=head3 get_channel

  my $chan_st = $irc->state->get_channel($channame);

If the channel is found, returns a Channel struct with the following accessor
methods:

=head4 nicknames

  my @users = keys %{ $chan_st->nicknames };

A HASH whose keys are the users present on the channel.

If a user has status modes, the values are an ARRAY of status prefixes (f.ex,
o => '@', v => '+', ...)

=head4 status_prefix_for


=head4 topic

  my $topic_st = $chan_st->topic;
  my $topic_as_string = $topic_st->topic();

The Topic struct provides information about the current channel topic via
accessors:

=over

=item *

B<topic> is the actual topic string

=item *

B<set_at> is the timestamp of the topic change

=item *

B<set_by> is the topic's setter

=back



=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut

