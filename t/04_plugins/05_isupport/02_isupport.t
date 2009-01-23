use strict;
use warnings;
use POE qw(Wheel::SocketFactory);
use POE::Component::IRC;
use POE::Component::IRC::Plugin::ISupport;
use POE::Component::IRC::Test::Harness;
use Socket;
use Test::More tests => 5;

my $irc = POE::Component::IRC->spawn( plugin_debug => 1 );
my $ircd = POE::Component::IRC::Test::Harness->spawn(
    Alias     => 'ircd',
    Auth      => 0,
    AntiFlood => 0,
);
$irc->plugin_add(ISupport => POE::Component::IRC::Plugin::ISupport->new(
    Channels => ['#chan1', '#chan2'],
));

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            _config_ircd 
            _shutdown 
            irc_001 
            irc_isupport
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

sub irc_isupport {
    my ($sender, $heap, $plugin) = @_[SENDER, HEAP, ARG0];
    my $irc = $sender->get_heap();

    return if $heap->{got_isupport};
    $heap->{got_isupport}++;

    pass('irc_isupport');
    isa_ok($plugin, 'POE::Component::IRC::Plugin::ISupport');
    my @keys = $plugin->isupport_dump_keys();
    ok($plugin->isupport(pop @keys), "Queried a parameter");

    $irc->yield('quit');
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

