# Proledo

Bewegte Hintergründe für Macs mit OLED-Display, damit sich nichts einbrennt.

Proledo sitzt in der Menüleiste. Du gibst einen YouTube-Link ein, das Video wird lokal gespeichert und läuft als Hintergrund auf dem Schreibtisch. Für jeden Monitor kannst du ein eigenes Video wählen oder ihn auslassen.

## Was die App kann

- YouTube-Videos ohne Ton laden, in der Qualität deiner Wahl
- Bei langen Videos nur einen Ausschnitt laden, zum Beispiel 10 Minuten aus einem 12-Stunden-Video
- Pro Monitor ein eigenes Video, auch hochkant
- Menüleiste und Dock pro Monitor ausblenden, sie kommen zurück, sobald die Maus an den Rand fährt
- Pausiert von selbst, wenn der Schreibtisch verdeckt ist, der Mac gesperrt ist oder im Akkubetrieb läuft
- Hält den Bildschirm nie wach
- Eigene Videodateien gehen auch

## Voraussetzungen

- macOS 14 oder neuer
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) für YouTube-Downloads
- [ffmpeg](https://ffmpeg.org) für Ausschnitte

```bash
brew install yt-dlp ffmpeg
```

## Bauen

```bash
./build.sh
open build/Proledo.app
```

Das Icon lässt sich mit `swift Tools/make-icon.swift <Ordner>.iconset` neu erzeugen und mit `iconutil` in `Resources/Proledo.icns` umwandeln.

## Hinweis

Lade nur Videos herunter, die du nutzen darfst. Die Nutzungsbedingungen von YouTube schränken Downloads ein.
