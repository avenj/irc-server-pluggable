package IRC::Server::Pluggable::IRC::Filter;
our $VERSION = 0;

## POE::Filter::IRCD adapted to accomodate IRCv3
## ... changes will likely be pushed upstream once I've given them
## a solid go

use strictures 1;
use Carp;

use parent 'POE::Filter';


sub _PUT_LITERAL () { 1 }


my $g = {
  space      => qr/\x20+/o,
  trailing_space  => qr/\x20*/o,
};

my $irc_regex = qr/^
  (?:
    \x40                # '@'-prefixed IRCv3.2 messsage tags.
    (\S+)               # Semi-colon delimited key=value list
    $g->{'space'}
  )?
  (?:
    \x3a                #  : comes before hand
    (\S+)               #  [prefix]
    $g->{'space'}       #  Followed by a space
  )?                    # but is optional.
  (
    \d{3}|[a-zA-Z]+     #  [command]
  )                     # required.
  (?:
    $g->{'space'}       # Strip leading space off [middle]s
    (                   # [middle]s
      (?:
        [^\x00\x0a\x0d\x20\x3a]
        [^\x00\x0a\x0d\x20]*
      )                 # Match on 1 of these,
      (?:
        $g->{'space'}
        [^\x00\x0a\x0d\x20\x3a]
        [^\x00\x0a\x0d\x20]*
      )*                # then match as many of these as possible
    )
  )?                    # otherwise dont match at all.
  (?:
    $g->{'space'}\x3a   # Strip off leading spacecolon for [trailing]
    ([^\x00\x0a\x0d]*)  # [trailing]
  )?                    # [trailing] is not necessary.
  $g->{'trailing_space'}
$/x;

sub new {
  my $type = shift;
  croak "$type requires an even number of parameters" if @_ % 2;
  my $buffer = { @_ };
  $buffer->{uc $_} = delete $buffer->{$_} for keys %{ $buffer };
  $buffer->{BUFFER} = [];
  return bless $buffer, $type;
}

sub debug {
  my $self = shift;
  my $value = shift;

  if ( defined $value ) {
    $self->{DEBUG} = $value;
     return $self->{DEBUG};
  }

  $self->{DEBUG} = $value
}

sub get {
  my ($self, $raw_lines) = @_;
  my $events = [];

  for my $raw_line (@$raw_lines) {
    warn "->$raw_line \n" if $self->{DEBUG};

    if ( my($tags, $prefix, $command, $middles, $trailing)
           = $raw_line =~ m/$irc_regex/ ) {

      my $event = { raw_line => $raw_line };

      if ($tags) {
        for my $tag_pair (split ';', $tags) {
          my ($thistag, $thisval) = split /=/, $tag_pair;
          $event->{tags}->{$thistag} = $thisval
        }
      }

      $event->{prefix} = $prefix if $prefix;
      $event->{command} = uc $command;
      $event->{params} = [] if defined ( $middles ) || defined ( $trailing );

      push @{$event->{params}}, (split /$g->{'space'}/, $middles)
        if defined $middles;
      push @{$event->{params}}, $trailing if defined $trailing;
      push @$events, $event;
    } else {
      warn "Received line $raw_line that is not IRC protocol\n";
    }
  }
  return $events;
}

sub get_one_start {
  my ($self, $raw_lines) = @_;
  push @{ $self->{BUFFER} }, $_ for @$raw_lines;
}

sub get_one {
  my $self = shift;
  my $events = [];

  if ( my $raw_line = shift ( @{ $self->{BUFFER} } ) ) {
    warn "->$raw_line \n" if $self->{DEBUG};

    if ( my($tags, $prefix, $command, $middles, $trailing)
       = $raw_line =~  m/$irc_regex/ ) {

      my $event = { raw_line => $raw_line };

      if ($tags) {
        for my $tag_pair (split ';', $tags) {
          my ($thistag, $thisval) = split /=/, $tag_pair;
          $event->{tags}->{$thistag} = $thisval
        }
      }

      $event->{prefix} = $prefix if $prefix;
      $event->{command} = uc $command;
      $event->{params} = [] if defined ( $middles ) || defined ( $trailing );

      push @{$event->{params}}, (split /$g->{'space'}/, $middles)
        if defined $middles;
      push @{$event->{params}}, $trailing if defined $trailing;
      push @$events, $event;
    } else {
      warn "Received line $raw_line that is not IRC protocol\n";
    }
  }

  $events
}

sub get_pending {
  return;
}

sub put {
  my ($self, $events) = @_;
  my $raw_lines = [];

  for my $event (@$events) {

    if (ref $event eq 'HASH') {
      my $colonify = defined $event->{colonify} ? 
        $event->{colonify} : $self->{COLONIFY} ;

      if ( _PUT_LITERAL || _checkargs($event) ) {
        my $raw_line = '';

        if ( $event->{tags} and ref $event->{tags} eq 'HASH' ) {
          $raw_line .= '@';
          my @tags = %{ $event->{tags} };
          while (my ($thistag, $thisval) = splice @tags, 0, 2) {
            $raw_line .= $thistag . ( defined $thisval ? '='.$thisval : '' );
            $raw_line .= ';' if @tags;
          }
          $raw_line .= ' ';
        }

        $raw_line .= (':' . $event->{prefix} . ' ') if exists $event->{prefix};
        $raw_line .= $event->{command};

        if ( $event->{params} and ref $event->{params} eq 'ARRAY' ) {
          my $params = [ @{ $event->{params} } ];
          $raw_line .= ' ';
          my $param = shift @$params;
          while (@$params) {
            $raw_line .= $param . ' ';
            $param = shift @$params;
          }
          $raw_line .= ':' if $param =~ m/\x20/ or $colonify;
          $raw_line .= $param;
        }

        push @$raw_lines, $raw_line;
        warn "<-$raw_line \n" if $self->{DEBUG};
      } else {
        next;
      }

    } else {
      warn __PACKAGE__ . " non hashref passed to put(): \"$event\"\n";
      push @$raw_lines, $event if ref $event eq 'SCALAR';
    }
  }

  $raw_lines
}

sub clone {
  my $self = shift;
  my $nself = { };
  $nself->{$_} = $self->{$_} for keys %{ $self };
  $nself->{BUFFER} = [ ];
  return bless $nself, ref $self;
}

# This thing is far from correct, dont use it.
sub _checkargs {
  my $event = shift || return;
  warn("Invalid characters in prefix: " . $event->{prefix} . "\n")
    if ($event->{prefix} =~ m/[\x00\x0a\x0d\x20]/);
  warn("Undefined command passed.\n")
    unless ($event->{command} =~ m/\S/o);
  warn("Invalid command: " . $event->{command} . "\n")
    unless ($event->{command} =~ m/^(?:[a-zA-Z]+|\d{3})$/o);
  foreach my $middle (@{$event->{'middles'}}) {
    warn("Invalid middle: $middle\n")
      unless ($middle =~ m/^[^\x00\x0a\x0d\x20\x3a][^\x00\x0a\x0d\x20]*$/);
  }
  warn("Invalid trailing: " . $event->{'trailing'} . "\n")
    unless ($event->{'trailing'} =~ m/^[\x00\x0a\x0d]*$/);
}

1;

__END__

=head1 LICENSE

Adapted with IRCv3 extensions by Jon Portnoy <avenj@cobaltirc.org>

L<POE::Filter::IRCD> is copyright Chris Williams and Jonathan Steinert

This module may be used, modified, and distributed under the same terms as 
Perl itself. 
Please see the license that came with your Perl distribution for details.

=head1 SEE ALSO

L<POE>

L<POE::Filter>

L<POE::Filter::Stackable>

L<POE::Component::Server::IRC>

L<POE::Component::IRC>

L<Parse::IRC>

=cut
