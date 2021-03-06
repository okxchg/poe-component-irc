use strict;
use warnings FATAL => 'all';
use lib 't/inc';
use POE;
use POE::Component::IRC;
use POE::Component::IRC::Plugin::NickReclaim;
use POE::Component::Server::IRC;
use Test::More tests => 6;

my $bot1 = POE::Component::IRC->spawn(
    Flood        => 1,
    plugin_debug => 1,
    alias        => 'bot1',
);
my $bot2 = POE::Component::IRC->spawn(
    Flood        => 1,
    plugin_debug => 1,
    alias        => 'bot2',
);
my $ircd = POE::Component::Server::IRC->spawn(
    Auth      => 0,
    AntiFlood => 0,
);

$bot2->plugin_add(NickReclaim => POE::Component::IRC::Plugin::NickReclaim->new(
    poll => 1,
));

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            ircd_listener_add
            ircd_listener_failure
            _shutdown
            irc_001
            irc_433
            irc_nick
            irc_disconnected
        )],
    ],
);

$poe_kernel->run();

sub _start {
    my ($kernel) = $_[KERNEL];

    $ircd->yield('register', 'all');
    $ircd->yield('add_listener');
    $kernel->delay(_shutdown => 60, 'Timed out');
}

sub ircd_listener_failure {
    my ($kernel, $op, $reason) = @_[KERNEL, ARG1, ARG3];
    $kernel->yield('_shutdown', "$op: $reason");
}

sub ircd_listener_add {
    my ($kernel, $heap, $port) = @_[KERNEL, HEAP, ARG0];
    $heap->{port} = $port;

    $bot1->yield(register => 'all');
    $bot1->yield(connect => {
        nick    => 'TestBot1',
        server  => '127.0.0.1',
        port    => $port,
    });
}

sub irc_001 {
    my $irc = $_[SENDER]->get_heap();
    pass($irc->session_alias() . ' (nick=' . $irc->nick_name() .') logged in');
    return if $irc != $bot1;

    $bot2->yield(register => 'all');
    $bot2->yield(connect => {
        nick    => 'TestBot1',
        server  => '127.0.0.1',
        port    => $_[HEAP]->{port},
    });
}

sub irc_433 {
    my $irc = $_[SENDER]->get_heap();
    pass($irc->session_alias . ' (nick=' . $irc->nick_name() .') nick collision');
    $bot1->yield('quit');
}

sub irc_nick {
    my ($sender, $new_nick) = @_[SENDER, ARG1];
    my $irc = $sender->get_heap();

    is($new_nick, 'TestBot1', $irc->session_alias . ' reclaimed nick ' . $irc->nick_name());
    $irc->yield('quit');
}

sub irc_disconnected {
    my ($kernel, $sender, $heap) = @_[KERNEL, SENDER, HEAP];
    my $irc = $sender->get_heap();

    pass($irc->session_alias . ' (nick=' . $irc->nick_name() .') disconnected');
    $heap->{count}++;
    $kernel->yield('_shutdown') if $heap->{count} == 2;
}

sub _shutdown {
    my ($kernel, $error) = @_[KERNEL, ARG0];
    fail($error) if defined $error;

    $kernel->alarm_remove_all();
    $ircd->yield('shutdown');
    $bot1->yield('shutdown');
    $bot2->yield('shutdown');
}

