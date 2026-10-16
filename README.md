# micduck

Turns your music down while you're talking into your Mac's microphone, and back
up when you stop.

I wrote it for voice dictation into [Claude Code](https://code.claude.com), which
has no hook for "started listening", but it works with anything that opens the
mic: dictation tools, Zoom, Meet, voice notes.

Using [Hammerspoon](https://www.hammerspoon.org)?
[MicDuck.spoon](https://github.com/dabeeeenster/MicDuck.spoon) does the same
inside it, with no separate app to run.

## How it works

micduck is a small Swift program that runs in the background. It asks CoreAudio
to tell it when any process starts or stops using the default input device
(`kAudioDevicePropertyDeviceIsRunningSomewhere`), and follows the default
device as it changes, e.g. when AirPods connect. It doesn't poll, so between
mic changes it sleeps and costs nothing. It doesn't record or read any audio,
so it needs no microphone permission.

When the mic opens, it saves the current volume of **Spotify** and **Apple
Music** (whichever are running) and fades them down to 50% over 0.2 seconds.
When the mic closes, it fades them back. If micduck is stopped mid-duck, it
restores the volume on the way out.

## Install

Needs macOS and the Xcode command line tools (`xcode-select --install`).

```sh
git clone https://github.com/dabeeeenster/micduck.git
cd micduck
make install
```

This builds the binary into `~/.local/bin/micduck` and installs a LaunchAgent
so it starts at login. The first time it turns the music down, macOS asks
whether micduck may control Spotify or Music; allow it.

Pick a different level, in percent of the player's volume:

```sh
make install DUCK_TO=40
```

Or run it in the foreground to try it out: `./micduck 40`.

Logs go to `~/Library/Logs/micduck.log`.

## Uninstall

```sh
make uninstall
```

## Caveats

- Any app holding the mic open counts. Some dictation apps keep it open all the
  time, which would keep the music down.
- Only the default input device is watched.
- If you change the music volume while ducked, it's overwritten when the mic
  closes.

## License

MIT
