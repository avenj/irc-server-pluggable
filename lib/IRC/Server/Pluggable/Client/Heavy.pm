package IRC::Server::Pluggable::Client::Heavy;

use 5.12.1;
use Moo;
use POE;
use Carp 'confess';

extends 'IRC::Server::Pluggable::Client::Lite';
#### TODO
## CAP negotiation.
##   We have multi-prefix support in our WHO parser.
##   Filter supports tags; we can support intents and receive server-time
##   Need sasl, extended-join/-notify, tls
## ISON  ?
## NAMES
## timers to issue WHO periodically for seen operators
## methods to check for shared channels
##  hooks in quit/part/disconnect to clear no-longer-seen users/channels

sub State () { 'IRC::Server::Pluggable::Client::Heavy::State' }


use MooX::Role::Pluggable::Constants;

use IRC::Server::Pluggable qw/
  Client::Heavy::State

  IRC::Event
  
  Utils
  Utils::Parse::CTCP

  Types
/;


with 'IRC::Server::Pluggable::Role::Interface::Client';


has state => (
  lazy    => 1,
  is      => 'ro',
  clearer => '_clear_state',
  writer  => '_set_state',
  default => sub {
    IRC::Server::Pluggable::Client::Heavy::State->new
  },
);


### Overrides.

## FIXME override _send to do flood prot ?

around ircsock_disconnect => sub {
  my $orig = shift;
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($conn, $str) = @_[ARG0, ARG1];
  
  $self->_clear_conn if $self->_has_conn;
  
  my $connected_to = $self->state->server_name;
  $self->_set_state( $self->_build_state );
  
  $self->emit( 'irc_disconnected', $str, $connected_to );
};

around _ctcp => sub {
  my $orig = shift;
  my ($kernel, $self)        = @_[KERNEL, OBJECT];
  my ($type, $target, @data) = @_[ARG0 .. $#_];

  $type = uc $type;

  if ($type eq 'ACTION' && $self->state->has_capabs('intents')) {
    $self->send(
      ev(
        command => 'privmsg',
        params  => [ $target, join(' ', @data) ],
        tags    => { intent => 'ACTION' },
      )
    )
  } else {
    my $quoted = ctcp_quote( join(' ', $type, @data) );
    $self->send(
      ev(
        command => 'privmsg',
        params  => [ $target, $quoted ],
      )
    )
  }
};


### Public.
sub get_prefix_hash {
  my ($self) = @_;

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

  \%prefixes
}

## FIXME these should maybe have POE counterparts
sub monitor {
  ## FIXME transparently use NOTIFY if no MONITOR support?
}

sub unmonitor {
  ## FIXME
}

sub who {
  my ($self, $target, $whox) = @_;

  if ($whox || $self->state->get_isupport('whox')) {
    ## Send WHOX, hope for a compliant implementation.
    $self->send( 
      ev( 
        command => 'who', params => [ $orig, '%tcnuhafr,912' ] 
      ) 
    );
  } else {
    ## No WHOX, send WHO.
    $self->send(
      ev( 
        command => 'who', params => [ $orig ] 
      )
    );
  }

  $self
}

### Our handlers.

sub P_preregister {
  my (undef, $self) = splice @_, 0, 2;

  ## Negotiate CAPAB
  my @enabled_caps = qw/
    away-notify
    account-notify
    extended-join
    intents
    multi-prefix
    server-time
  /;

  for my $cap (@enabled_caps) {
    ## Spec says the server should ACK or NAK the whole set.
    ## ... not sure if sending one at a time is the right thing to do
    $self->send( 
      ev( command => 'cap', params => [ 'req', $cap ] ),
      ev( command => 'cap', params => [ 'end' ] )
    )
  }

  EAT_NONE
}

sub N_irc_cap {
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };

  my (undef, $cmd, $capstr) = @{ $ircev->params };
  my @caps = split ' ', $capstr;

  if ($cmd eq 'ack') {
    for my $thiscap (@caps) {
      my $maybe_prefix = substr $thiscap, 0, 1;
      if (grep {; $_ eq $maybe_prefix } ('-', '=', '~')) {
        my $actual = $thiscap;
        substr $actual, 0, 1, '';
        
        for ($maybe_prefix) {
          when ('-') {
            ## Negated.
            $self->state->clear_capabs($actual);
            $self->emit( 'cap_cleared', $actual );
          }
          when ('=') {
            ## Sticky.
            ## We don't track these, at the moment.
            $self->state->add_capabs($actual);
            $self->emit( 'cap_added', $actual );
          }
          when ('~') {
            ## Requires an ACK
            $self->state->add_capabs($actual);
            $self->emit( 'cap_added', $actual );
            $self->send(
              ev( command => 'cap', params  => [ 'ack', $actual ] )
            )
          }
          
        }

      } else {
        ## Not prefixed.
        $self->state->add_capabs($thiscap);
        $self->emit( 'cap_added', $thiscap );
      }

    }
  }

  EAT_NONE
}

sub N_irc_001 {
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };

  $self->state->_set_server_name( $ircev->prefix );

  $self->state->_set_nick_name(
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

 $self->state->isupport_struct->extend_with( $_, $isupport{$_} )
   for keys %isupport;

  EAT_NONE
}

sub N_irc_332 {
  ## Topic
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };

  my (undef, $target, $topic) = @{ $ircev->params };

  my $chan_obj = $self->state->get_channel($target);
  $chan_obj->topic->topic( $topic );

  EAT_NONE
}

sub N_irc_333 {
  ## Topic setter & TS
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };

  my (undef, $target, $setter, $ts) = @{ $ircev->params };
 
  my $chan_obj = $self->state->get_channel($target);
  $chan_obj->topic->set_at( $ts );
  $chan_obj->topic->set_by( $setter );

  EAT_NONE
}

sub N_irc_352 {
  ## WHO reply
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };

  ## FIXME get / update other vars:
  my (
    undef,      ## Target (us)
    $target,    ## Channel
    undef,      ## Username
    undef,      ## Hostname
    undef,      ## Servername
    $nick,      ## Nickname
    $status,    ## H*@ f.ex
    undef       ## Hops + Realname
  ) = @{ $ircev->params };
  
  my $chan_obj = $self->state->get_channel($target);
  my $user_obj = $self->state->get_user($nick);
  return EAT_NONE unless defined $chan_obj and defined $user_obj;
  
  my @status_bits = split '', $status;
  my $here_or_not = shift @status_bits;
  $here_or_not eq 'G' ? $user_obj->is_away(1) : $user_obj->is_away(0) ;
  ## FIXME track these via WHO on a timer if we don't have away-notify?

  if (grep {; $_ eq '*' } @status_bits) {
    $user_obj->is_oper(1);
    ## FIXME track these (timer?)
  }

  my %pfx_chars   = map {; $_ => 1 } values %{ $self->get_prefix_hash };
  my $current_ref = $chan_obj->present->{ $self->upper($nick) };
  my %current     = map {; $_ => 1 } @$current_ref;

  ## This supports IRCv3.1 multi-prefix extensions:
  for my $bit (@status_bits) {
    push @$current_ref, $bit
      if exists $pfx_chars{$bit}
      and not $current{$bit};
  }

  EAT_NONE
}

sub irc_354 {
  ## WHOX reply
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };
  ## FIXME check for correctness
  ## Seems these may vary, esp. with (old?) ircu
  ## Cannot seem to find very many people with useful information on the
  ## topic, not sure I can be arsed to dig deep on it myself . . .
  my (
    $tag,       ## Numeric tag
    $channel,   ## Channel
    $user,      ## Username
    $host,      ## Hostname
    $nick,      ## Nickname
    $status,    ## H*@ etc
    $account,   ## Account or '0'
    $realname   ## Realname (no hops)
  ) = @{ $ircev->params };

  my @status_bits = split '', $status;
  my $here_or_not = shift @status_bits;
  $here_or_not eq 'G' ? $user_obj->is_away(1) : $user_obj->is_away(0) ;
  ## FIXME rest of status parser
  ## FIXME update Structs appropriately


  ## FIXME hum. may reach end-of-who before we have all replies,
  ##  according to ircu behavior?

  EAT_NONE
}


sub irc_730 {
  ## MONONLINE
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };

  return unless $self->state->get_isupport('monitor');

  my @targets = split /,/, $ircev->params->[1];
  $self->emit( 'monitor_online', @targets );

  EAT_NONE
}

sub irc_731 {
  ## MONOFFLINE
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };

  return unless $self->state->get_isupport('monitor');

  my @targets = split /,/, $ircev->params->[1];
  $self->emit( 'monitor_offline', @targets );

  EAT_NONE
}

sub irc_734 {
  ## MONLISTFULL
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };

  return unless $self->state->get_isupport('monitor');

  my (undef, $limit, $targets) = @{ $ircev->params };
  $self->emit( 'monitor_list_full', $limit, split(/,/, $targets) );

  EAT_NONE
}

## FIXME get NAMES reply

sub N_irc_account {
  ## account-notify
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };
  
  my ($nick, $user, $host) = parse_user( $ircev->prefix );
  
  my $user_obj = $self->state->get_user($nick);
  unless ($user_obj) {
    warn "Received ACCOUNT from server for unknown user $nick";
    return EAT_NONE
  }
  
  my $acct = $ircev->params->[0];
  if ($acct eq '*') {
    $user_obj->account('');
    $self->emit( 'account_notify_cleared', $nick );
  } else {
    $user_obj->account($acct);
    $self->emit( 'account_notify_set', $nick, $acct );
  }

  EAT_NONE
}

sub N_irc_away {
  ## away-notify
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };

  my ($nick, $user, $host) = parse_user( $ircev->prefix );

  my $user_obj = $self->state->get_user($nick);
  unless ($user_obj) {
    warn "Received AWAY from server for unknown user $nick";
    return EAT_NONE
  }

  if (@{ $ircev->params }) {
    ## Went away.
    $user_obj->is_away(1);
  } else {
    ## Came back.
    $user_obj->is_away(0);
  }

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

  my $chan_obj = $self->state->get_channel($target);

  my(@always, @whenset);
  if (my $cmodes = $self->state->get_isupport('chanmodes')) {
    my ($list, $always, $whenset) = split /,/, $cmodes;
    push @always,  split('', $list), split('', $always);
    push @whenset, split '', $whenset;
  }

  ## FIXME
  ##  Needs to use mode_to_array
  ##  Needs to be able to cancel earlier changes e.g. -o+o-o+o X X X X
  my $mode_hash = mode_to_hash( $modestr,
    params  => [ @params ],
    ( @always  ?  (param_always => \@always)  : () ),
    ( @whenset ?  (param_set    => \@whenset) : () ),
  );

  my %prefixes = %{ $self->get_prefix_hash };

  MODE_ADD: for my $char (keys %{ $mode_hash->{add} }) {
    next MODE_ADD unless exists $prefixes{$char}
      and ref $mode_hash->{add}->{$char} eq 'ARRAY';
    my $param = $mode_hash->{add}->{$char}->[0];
    my $this_user;
    unless ($this_user = $chan_obj->present->{ $self->upper($param) }) {
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
    unless ($this_user = $chan_obj->present->{ $self->upper($param) }) {
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

  ## FIXME does our own JOIN include account in extended-join ?
  my ($account, $orig);
  if ($self->state->has_capabs('extended-join')) {
    ($account, $orig) = @{ $ircev->params };
    $account = undef if $account eq '*';
  } else {
    $orig = $ircev->params->[0];
  }

  my $target  = uc_irc( $orig, $casemap );
  $nick       = uc_irc( $nick, $casemap );

  if ( eq_irc($nick, $self->state->nick_name, $casemap) ) {
    ## Us. Add new Channel struct.
    $self->state->channels->{$target} = Channel->new(
      name      => $orig,
      nicknames => {},
      topic     => Topic->new(
        set_by => '',
        set_at => 0,
        topic  => '',
      ),
    );
    ## ... and request a WHO(X):
    $self->who( $orig );
 } else {
    ##  Not us. Add or update User struct.
    $self->state->update_user( $nick,
      user => $user,
      host => $host,
      ( defined $account ? (account => $account) : () ),
    );
    $self->who( $nick );
  }

  my $chan_obj = $self->state->channels->{$target};
  $chan_obj->present->{$nick} = [];

  EAT_NONE
}

sub N_irc_part {
  my (undef, $self) = splice @_, 0, 2;
  my $ircev = ${ $_[0] };

  ## FIXME object api for new State
  ## FIXME check for users we no longer share channels with

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

  ## FIXME object api for new State

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

  ## FIXME object api for new State

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

IRC::Server::Pluggable::Client::Heavy - Stateful IRCv3 client

=head1 SYNOPSIS

FIXME

=head1 DESCRIPTION

This is a mostly-IRCv3-compatible state-tracking subclass of 
L<IRC::Server::Pluggable::Client::Lite>.

=head2 IRCv3 compatibility

Supported:

B<away-notify>

B<account-notify>

B<extended-join>

B<intents>

B<multi-prefix>

B<server-time>

B<MONITOR>


B<sasl> and B<tls> are currently missing. TLS may be a challenge due to a lack of
STARTTLS-compatible POE Filters/Components; input/patches welcome, of course.



FIXME this is the POD as extracted from Lite, it needs to move to Heavy::State
POD:


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

