# Proledo

Moving wallpapers for Macs with a PROLED or OLED display, so nothing burns in.

Made for the MacBook Pro with PROLED XDR display, works on any Mac and any external monitor. Proledo lives in your menu bar. Paste a YouTube link, the video gets saved locally and plays as your desktop background. Every monitor can have its own video, or none at all.

## What it does

- Downloads YouTube videos without sound, in the quality you pick
- Grabs just a slice of long videos, like 10 minutes out of a 12-hour one
- Lets you choose a video per monitor, portrait screens included
- Hides the menu bar and Dock per monitor, they come back when your mouse hits the edge
- Pauses on its own when the desktop is covered, the Mac is locked or running on battery
- Has a power saving mode that plays a lighter 30 fps copy of each video
- Never keeps your screen awake
- Works with your own video files too

## Install

Grab `Proledo.zip` from the [latest release](https://github.com/drieken/Proledo/releases/latest), unzip it and move Proledo to your Applications folder.

The app isn't notarized yet, so macOS blocks it on first launch. Right-click it and choose **Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Proledo.app
```

## Requirements

- macOS 14 or later
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) for YouTube downloads
- [ffmpeg](https://ffmpeg.org) for clips

```bash
brew install yt-dlp ffmpeg
```

## Build

```bash
./build.sh
open build/Proledo.app
```

To redraw the icon, run `swift Tools/make-icon.swift <folder>.iconset` and turn it into `Resources/Proledo.icns` with `iconutil`.

## Note

Only download videos you're allowed to use. YouTube's terms of service restrict downloads.
