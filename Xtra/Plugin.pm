package Plugins::Xtra::Plugin;

#
# LMS-Xtra
#
# Copyright (c) 2023 Craig Drummond <craig.p.drummond@gmail.com>
#
# MIT license.
#

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

my $log = Slim::Utils::Log->addLogCategory({
    'category' => 'plugin.xtra',
    'defaultLevel' => 'ERROR',
    'description' => 'PLUGIN_XTRA'
});

my $prefs = preferences('plugin.xtra');
my $serverPrefs = preferences('server');

sub getDisplayName {
    return 'PLUGIN_XTRA';
}

sub initPlugin {
    my $class = shift;
    $class->initCLI();
    $class->SUPER::initPlugin(@_);
}

sub shutdownPlugin {
}

sub initCLI {
    Slim::Control::Request::addDispatch(['xtra', '_cmd'], [1, 0, 1, \&_cliCommand]);
}

sub _playPreset {
    my $request = shift;
    my $client = $request->client();
    my $presets = $serverPrefs->client($client)->get('presets');
    my $num = $request->getParam('num');
    main::INFOLOG && $log->is_info && $log->info('Preset ' . $num);
    my $val = int($num);
    if ($val<1 || $val>10) {
        $request->setStatusBadParams();
        return;
    }
    my $url = $presets->[$val - 1]->{URL};
    main::INFOLOG && $log->is_info && $log->info('URL ' . $url);
    if (!$url) {
        $request->setStatusBadParams();
        return;
    }
    $client->execute(['playlist', 'clear']);
    $client->execute(['playlist', 'play', $url]);
    $request->setStatusDone();
}

sub _cliCommand {
    my $request = shift;

    # check this is the correct query.
    if ($request->isNotCommand([['xtra']])) {
        $request->setStatusBadDispatch();
        return;
    }

    my $cmd = $request->getParam('_cmd');
    main::INFOLOG && $log->is_info && $log->info('Xtra cmd: ' . $cmd);
    my $client = $request->client();
    if ($request->paramUndefinedOrNotOneOf($cmd, ['preset', 'btn']) ) {
        $request->setStatusBadParams();
        return;
    }

    if ($cmd eq 'preset') {
        _playPreset($request);
        return;
    }

    if ($cmd eq 'btn') {
        if (Slim::Player::Playlist::count($client)>0) {
            my $num = $request->getParam('num');
            main::INFOLOG && $log->is_info && $log->info('Btn ' . $num);
            my $val = int($num);
            if ($val == 1) {
                $client->execute(['button', 'jump_rew']);
                $request->setStatusDone();
            } elsif ($val == 2) {
                $client->execute(['playlist', 'index', '+1']);
                $request->setStatusDone();
            } else {
                $request->setStatusBadParams();
            }
        } else {
            _playPreset($request);
        }
        return;
    }
    $request->setStatusBadParams();
}

1;
