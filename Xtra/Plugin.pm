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
use Time::HiRes qw/gettimeofday/;

my $log = Slim::Utils::Log->addLogCategory({
    'category' => 'plugin.xtra',
    'defaultLevel' => 'ERROR',
    'description' => 'PLUGIN_XTRA'
});

my $prefs = preferences('plugin.xtra');
my $serverPrefs = preferences('server');
my %lastPresetIdxs = ();
my %lastPresetTimes = ();
my %lastCommandTimes = ();

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

sub _cyclePresets {
    my $request = shift;
    my $client = $request->client();
    my $cid = $client->id();
    my $lastPresetIdx = exists $lastPresetIdxs{$cid} ? $lastPresetIdxs{$cid} : -1;
    my $lastPresetTime = exists $lastPresetTimes{$cid} ? $lastPresetTimes{$cid} : 0;
    my $presets = $serverPrefs->client($client)->get('presets');
    my $now = time();
    my $idx = $lastPresetTime==0 || ($now - $lastPresetTime)>600 || $lastPresetIdx==-1 || Slim::Player::Playlist::count($client)==0 ? 0 : ($lastPresetIdx+1);
    main::INFOLOG && $log->is_info && $log->info('IDX: ' . $idx . ', LIDX: ' . $lastPresetIdx . ', HAD: ' . $lastPresetIdxs{$cid});
    my $url = undef;
    # Find URL after current
    for (; $idx < 10; $idx++) {
        $url = $presets->[$idx]->{URL};
        if ($url) {
            main::INFOLOG && $log->is_info && $log->info('Found[1] @' . $idx);
            last;
        }
    }
    if (!$url) {
        # Just find first URL
        for ($idx = 0; $idx < 10; $idx++) {
            $url = $presets->[$idx]->{URL};
            if ($url) {
                main::INFOLOG && $log->is_info && $log->info('Found[2] @' . $idx);
                last;
            }
        }
    }
    if (!$url) {
        $request->setStatusBadParams();
        return;
    }
    main::INFOLOG && $log->is_info && $log->info('IDX: ' . $idx . ', URL: ' . $url);
    if (!$url) {
        $request->setStatusBadParams();
        return;
    }
    $client->execute(['playlist', 'clear']);
    $client->execute(['playlist', 'play', $url]);
    $request->setStatusDone();
    $lastPresetIdxs{$cid} = $idx;
    $lastPresetTimes{$cid} = $now;
    main::INFOLOG && $log->is_info && $log->info('STORE IDX: ' . $idx . ', URL: ' . $url . ', MAP: ' . $lastPresetIdxs{$cid});
}

sub _stopPlayOrPause {
    my $request = shift;
    my $client = $request->client();
    my $song = Slim::Player::Source::playingSong($client);
    my $command = 'play';
    if ($client->isPlaying()) {
         $command = 'pause';
        if (defined $song) {
            my $url = $song->currentTrack()->url;
            if ($url) {
                my $idx = rindex($url, "http", 0);
                if (0==$idx) {
                    $command = 'stop';
                }
            }
        }
    }
    main::INFOLOG && $log->is_info && $log->info('Send command ' . $command);
    $client->execute([$command]);
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
    if ($request->paramUndefinedOrNotOneOf($cmd, ['preset', 'btn', 'cycle-presets', 'stop-pause']) ) {
        $request->setStatusBadParams();
        return;
    }

    my $cid = $request->client()->id();
    my $lastCommandTime = exists $lastCommandTimes{$cid} ? $lastCommandTimes{$cid} : 0.0;
    my $now = gettimeofday;
    $lastCommandTimes{$cid} = $now;
    if (($now - $lastCommandTime)<0.250) {
        $request->setStatusBadParams();
        return;
    }

    if ($cmd eq 'cycle-presets') {
        _cyclePresets($request);
        return;
    }

    if ($cmd eq 'stop-pause') {
        _stopPlayOrPause($request);
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
