# Azure TTS Cached for PopClip

[中文说明](README.zh-CN.md)

A PopClip extension that turns selected text into speech with Azure AI Speech, caches the generated MP3, and plays it locally through VLC.

## Features

- Azure neural text-to-speech with configurable region, locale, and voice
- Local MP3 cache to avoid repeated API requests for the same text and settings
- Two playback rates: `1.0x` and `0.8x`
- Native pause/resume through VLC remote control
- Stable PopClip controls that remain visible while you listen
- Azure subscription key stored as a concealed PopClip secret

## Requirements

- macOS with [PopClip](https://www.popclip.app/)
- [VLC media player](https://www.videolan.org/vlc/)
- An Azure AI Speech resource and subscription key

The extension looks for VLC in these locations:

```text
/Applications/VLC.app/Contents/MacOS/VLC
/opt/homebrew/bin/vlc
/usr/local/bin/vlc
```

## Installation

1. Download or clone this repository.
2. Double-click `AzureTTSCached.popclipext` in Finder.
3. Confirm installation in PopClip.
4. Open the extension settings and enter your Azure subscription key.

Reinstall the extension package after updating its files.

## Configuration

| Option | Default | Description |
| --- | --- | --- |
| Azure Region | `eastus` | Region containing your Azure Speech resource |
| Azure Subscription Key | — | Speech resource API key, stored as a secret |
| Audio Output | `audio-16khz-32kbitrate-mono-mp3` | Azure audio output format |
| Locale | `en-US` | Speech synthesis locale |
| Voice | `en-US-JennyMultilingualNeural` | Azure neural voice name |

## Usage

Select text and use one of the three PopClip actions:

| Icon | Action |
| --- | --- |
| Waveform | Play from the beginning at `1.0x` |
| Play/Pause | Pause or resume the current VLC playback |
| Tortoise | Play from the beginning at `0.8x` |

Starting a new `1.0x` or `0.8x` action stops the previous playback. Pause and resume operate on the same VLC process, preserving the playback position.

## Cache and runtime files

Generated audio and player state are stored in:

```text
~/Library/Caches/PopClipAzureTTS
```

Playback speed is excluded from the audio cache key, so both speed actions reuse the same downloaded MP3. The cache key includes the selected text, Azure region, locale, voice, and output format.

To clear downloaded speech, quit active playback and remove the contents of that cache directory.

## Troubleshooting

- **The action shows an X:** verify that VLC is installed and that the Azure key and region are correct.
- **Nothing plays for new text:** confirm the Mac can reach the configured Azure Speech endpoint.
- **Cached text plays but new text does not:** the Azure request is likely failing; check the subscription key, region, quota, and network connection.
- **Pause/resume does not respond:** ensure no firewall or security tool is blocking VLC's local loopback control port.

VLC remote control binds only to `127.0.0.1` and uses a free port in the range `43177–43197`.

## Project structure

```text
AzureTTSCached.popclipext/
├── Config.yaml  # PopClip actions and settings
└── azure.sh     # Azure request, cache, VLC playback, and controls
```
