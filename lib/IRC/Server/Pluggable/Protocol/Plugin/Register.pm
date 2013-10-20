package IRC::Server::Pluggable::Protocol::Plugin::Register;
use Defaults::Modern;

## Conceptually based on POE::Component::Server::IRC::Plugin::Auth

use IRC::Server::Pluggable qw/
  Constants
  Types
/;

use POE qw/
  Component::Client::DNS
  Component::Client::Ident::Agent
/;


use Moo;
use namespace::clean;

has session_id => (
  lazy      => 1,
  is        => 'ro',
  writer    => 'set_session_id',
  predicate => 'has_session_id',
);

has proto => (
  weak_ref  => 1,
  lazy      => 1,
  is        => 'ro',
  writer    => 'set_proto',
  predicate => 'has_proto',
  isa       => HasMethods[qw/emit send_to_routes/],
);

has pending => (
  ## Keyed on $conn->wheel_id()
  lazy    => 1,
  is      => 'ro',
  isa     => HashRef,
  default => sub { {} },
);

has resolver => (
  lazy      => 1,
  is        => 'ro',
  writer    => 'set_resolver',
  predicate => 'has_resolver',
);

method Emitter_register ($proto) {
  $self->set_proto( $proto );

  POE::Session->create(
    object_states => [
      $self => [ qw/
        _start

        p_resolve_host
        p_got_host
        p_got_ipaddr

        p_fetch_ident
        ident_agent_reply
        ident_agent_error
      / ],
    ],
  );

  $proto->subscribe( $self, NOTIFY => 'connection' );

  EAT_NONE
}

method Emitter_unregister {
  $self->resolver->shutdown if $self->has_resolver;
  EAT_NONE
}

method N_connection ($proto, $connref) {
  my $conn = $$connref;

  $proto->send_to_routes(
    {
      command => 'NOTICE',
      params  => [ 'AUTH', '*** Checking Ident' ],
    },
    $conn->wheel_id
  );

  $proto->send_to_routes(
    {
      command => 'NOTICE',
      params  => [ 'AUTH', '*** Looking up your hostname...' ],
    },
    $conn->wheel_id
  );

  my $peeraddr = $conn->peeraddr;

  if (index($peeraddr, '127.') == 0 || $peeraddr eq '::1') {
    ## Connection from localhost.
    $proto->send_to_routes(
      {
        command => 'NOTICE',
        params  => [ 'AUTH', '*** Found your hostname' ],
      },
      $conn->wheel_id
    );

    $self->pending->{ $conn->wheel_id }->{host} = 'localhost';
    $self->_maybe_finished($conn);
  }

  $poe_kernel->call( $self->session_id => p_resolve_host => $conn );
  $poe_kernel->call( $self->session_id => p_fetch_ident  => $conn );

  EAT_NONE
}


method _maybe_finished ($conn) {
  my $ref;
  return unless $ref = $self->pending->{ $conn->wheel_id };

  return unless defined $ref->{host}
    and defined $ref->{ident};

  ## If we're done, tell our emitter.
  delete $self->pending->{ $conn->wheel_id };
  my $host  = $ref->{host}  eq '' ? undef : $ref->{host};
  my $ident = $ref->{ident} eq '' ? undef : $ref->{ident};
  $self->proto->emit( 'register_complete',
    $conn,
    { host => $host, ident => $ident }
  )
}


sub _start {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $self->set_session_id( $_[SESSION]->ID );

  $self->set_resolver(
    POE::Component::Client::DNS->spawn(
      Timeout => 10,
    ),
  );
}

sub p_resolve_host {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $conn = $_[ARG0];

  my $ipvers = $conn->protocol;

  ## Attempt to get PTR for peeraddr.
  my $response = $self->resolver->resolve(
    event => 'p_got_host',
    host  => $conn->peeraddr,
    type  => 'PTR',
    context => {
      conn => $conn,
      inet => $ipvers,
    },
  );

  $kernel->call( p_got_host => $response) if $response;
}

sub p_got_host {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $response = $_[ARG0];

  my $conn = $response->{context}->{conn};

  ## May have been disconnected.
  ## wheel() should have been cleared.
  return unless $conn->has_wheel and $conn->wheel;

  my $fail = sub {
    ## No PTR.
    $self->proto->send_to_routes(
      {
        command => 'NOTICE',
        params  => [ 'AUTH', "*** Couldn't look up your hostname" ],
      },
      $conn->wheel_id
    );

    $self->pending->{ $conn->wheel_id }->{host} = '';
    $self->_maybe_finished($conn);
  };

  return $fail->() if not defined $response->{response};
  my @answers = $response->{response}->answer();
  return $fail->() unless @answers;

  my $ipvers = $response->{context}->{inet};
  my $type   = $ipvers == 6 ? 'AAAA' : 'A' ;

  for my $ans (@answers) {
    my $hostname = $ans->rdatastr();

    ## Kill trailing '.' if present
    $hostname =~ s/\.$//;

    my $h_resp = $self->resolver->resolve(
      event => 'p_got_ipaddr',
      host  => $ans->rdatastr(),
      type  => $type,
      context => {
        conn => $conn,
        host => $hostname,
      },
    );

    if ($h_resp) {
      $kernel->call( $self->session_id => p_got_ipaddr => $h_resp)
    }
  }
}

sub p_got_ipaddr {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $response = $_[ARG0];

  my $conn = $response->{context}->{conn};

  return unless $conn->has_wheel and $conn->wheel;

  my $fail = sub {
    $self->proto->send_to_routes(
      {
        command => 'NOTICE',
        params  => [ 'AUTH', "*** Couldn't look up your hostname" ],
      },
      $conn->wheel_id
    );
    $self->pending->{ $conn->wheel_id }->{host} = '';
    $self->_maybe_finished($conn);
  };

  return $fail->() if not defined $response->{response};
  my @answers = $response->{response}->answer();
  return $fail->() unless @answers;

  my $hostname = $response->{context}->{host};
  my $peeraddr = $conn->peeraddr;

  for my $ans (@answers) {
    if ($ans->rdatastr() eq $peeraddr) {
      $self->proto->send_to_routes(
        {
          command => 'NOTICE',
          params  => [ 'AUTH', '*** Found your hostname' ],
        },
        $conn->wheel_id
      );

      $self->pending->{ $conn->wheel_id }->{host} = $hostname;
      $self->_maybe_finished($conn);

      return
    }
  }

  ## No matching answer.
  $self->proto->send_to_routes(
    {
      command => 'NOTICE',
      params  => [
        'AUTH',
        "*** Your forward and reverse DNS do not match",
      ],
    },
    $conn->wheel_id,
  );

  $self->pending->{ $conn->wheel_id }->{host} = '';
  $self->_maybe_finished($conn);
}

sub p_fetch_ident {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $conn = $_[ARG0];

  POE::Component::Client::Ident::Agent->spawn(
    PeerAddr => $conn->peeraddr,
    PeerPort => $conn->peerport,
    SockAddr => $conn->sockaddr,
    SockPort => $conn->sockport,
    BuggyIdentd => 1,
    TimeOut   => 10,
    Reference => $conn,
  );
}

sub ident_agent_reply {
  my ($kernel, $self)       = @_[KERNEL, OBJECT];
  my ($ref, $opsys, $other) = @_[ARG0 .. ARG2];

  my $conn = $ref->{Reference};

  return unless $conn->has_wheel and $conn->wheel;

  my $ident = uc $opsys eq 'OTHER' ? '' : $other ;

  $self->proto->send_to_routes(
    {
      command => 'NOTICE',
      params  => [ 'AUTH', "*** Got Ident response" ],
    },
    $conn->wheel_id
  );

  $self->pending->{ $conn->wheel_id }->{ident} = $ident;
  $self->_maybe_finished($conn);
}

sub ident_agent_error {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($ref, $error)   = @_[ARG0, ARG1];

  my $conn = $ref->{Reference};

  return unless $conn->has_wheel and $conn->wheel;

  $self->proto->send_to_routes(
    {
      command => 'NOTICE',
      params  => [ 'AUTH', '*** No Ident response' ],
    },
    $conn->wheel_id
  );

  $self->pending->{ $conn->wheel_id }->{ident} = '';
  $self->_maybe_finished($conn);
}

1;

=pod

=head1 NAME

IRC::Server::Pluggable::Protocol::Plugin::Register - DNS and Ident lookup

=head1 SYNOPSIS

Registers for:

  N_connection

Loaded via the B<autoloaded_plugins> attribute belonging to
L<IRC::Server::Pluggable::Protocol::Base>.

=head1 DESCRIPTION

L<IRC::Server::Pluggable::Protocol> plugin bridging
L<POE::Component::Client::DNS> and
L<POE::Component::Client::Ident::Agent>.

Listens for connection events and issues asynchronous DNS/identd lookups.

Emits B<register_complete> when DNS and identd lookups have finished
(with either success or failure); carries the
L<POEx::IRC::Backend::Connect> object and a hash containing
resolved C<host> / C<ident> keys (whose values are undefined if
lookups were unsuccessful):

  $protocol->emit( 'register_complete',
    $conn,
    { host => $host, ident => $ident }
  )

Also see L<IRC::Server::Pluggable::Protocol::Role::TS::Register>

Conceptually based on L<POE::Component::Server::IRC>'s Register plugin.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
