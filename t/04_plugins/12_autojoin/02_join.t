use strict;
use warnings;
use POE qw(Wheel::SocketFactory);
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::AutoJoin;
use POE::Component::IRC::Test::Harness;
use Socket;
use Test::More tests => 4;

my $irc = POE::Component::IRC::State->spawn( plugin_debug => 1 );
my $ircd = POE::Component::IRC::Test::Harness->spawn(
    Alias     => 'ircd',
    Auth      => 0,
    AntiFlood => 0,
);
$irc->plugin_add(AutoJoin => POE::Component::IRC::Plugin::AutoJoin->new(
    Channels => ['#chan1', '#chan2'],
));

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            _config_ircd 
            _shutdown 
            irc_001 
            irc_join
            irc_disconnected
        )],
    ],
);

$poe_kernel->run();

sub _start {
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    my $wheel = POE::Wheel::SocketFactory->new(
        BindAddress  => '127.0.0.1',
        BindPort     => 0,
        SuccessEvent => '_fake_success',
        FailureEvent => '_fake_failure',
    );

    if ($wheel) {
        my $port = ( unpack_sockaddr_in( $wheel->getsockname ) )[0];
        $kernel->yield(_config_ircd => $port );
        $heap->{count} = 0;
        $wheel = undef;
        $kernel->delay(_shutdown => 60);
        return;
    }
    
    $kernel->yield('_shutdown');
}

sub _config_ircd {
    my ($kernel, $port) = @_[KERNEL, ARG0];
    
    $kernel->post( 'ircd' => 'add_i_line' );
    $kernel->post( 'ircd' => 'add_listener' => { Port => $port } );
    
    $irc->yield(register => 'all');
    $irc->yield(connect => {
        nick    => 'TestBot1',
        server  => '127.0.0.1',
        port    => $port,
        ircname => 'Test test bot',
    });
}

sub irc_001 {
    my $irc = $_[SENDER]->get_heap();
    pass('Logged in');
}

sub irc_join {
    my ($sender, $heap, $where) = @_[SENDER, HEAP, ARG1];
    my $irc = $sender->get_heap();
    $heap->{joined}++;

    $where =~ /^#chan[12]$/
        ? pass("Joined channel $where")
        : fail("Joined wrong channel $where");
    ;
    
    $irc->yield('quit') if $heap->{joined} == 2;
}

sub irc_disconnected {
    my ($kernel) = $_[KERNEL];
    pass('irc_disconnected');
    $kernel->yield('_shutdown');
}

sub _shutdown {
    my ($kernel) = $_[KERNEL];
    $kernel->alarm_remove_all();
    $kernel->post(ircd => 'shutdown');
    $irc->yield('shutdown');
}

