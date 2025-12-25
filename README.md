# bing-wallpaper

A simple, cross-platform shell script that downloads Bing’s daily wallpaper and optionally sets it as your desktop background.

Based on the original project:  
https://github.com/thejandroman/bing-wallpaper

Supported environments:

- Fedora KDE
- Debian / Ubuntu
- macOS

---

## How it works

- Fetches Bing’s “image of the day” metadata (XML)
- Downloads the image in the chosen resolution
- Saves it under a local folder (default: `~/Pictures/bing-wallpapers`)
- Optionally sets it as the current wallpaper depending on your desktop environment:
  - KDE Plasma: `plasma-apply-wallpaperimage`
  - GNOME: `gsettings`
  - macOS: `osascript`

---

## Options

```text
-p, --picturedir <dir>       Download directory
                             (default: ~/Pictures/bing-wallpapers)

-m, --market <mkt>           Bing market / locale
                             (default: en-US)

-r, --resolution <res>       Image resolution
                             UHD | 1920x1200 | 1920x1080 | 800x480 | 400x240
                             (default: UHD)

-w, --set-wallpaper          Set the downloaded image as wallpaper

-f, --force                  Force re-download even if file exists

-q, --quiet                  Less output

-h, --help                   Show help
```

---

## First execution

Make the script executable:

```bash
chmod +x ./src/bing-wallpaper.sh
```

Run it:

```bash
./src/bing-wallpaper.sh -w -L -S -m pt-BR -r UHD
```

This will:
1. Download Bing’s image of the day
2. Save it locally
3. Set it as your wallpaper (when supported)

---

## Bing market codes (locales)

Bing supports many regional markets such as `en-US`, `pt-BR`, `en-GB`, etc.

Official list:

https://github.com/MicrosoftDocs/bing-docs/blob/main/bing-docs/bing-web-search/reference/market-codes.md

---

## Scheduling on Linux (Fedora KDE / Debian / Ubuntu)

If your distro uses **systemd**, the cleanest approach is a **user service + user timer**.

### 1) Move the script to a stable path

```bash
mkdir -p ~/.local/bin
cp ./src/bing-wallpaper.sh ~/.local/bin/bing-wallpaper.sh
chmod +x ~/.local/bin/bing-wallpaper.sh
```

### 2) Create a user service

```bash
cp ./src/linux/bing-wallpaper.service ~/.config/systemd/user/bing-wallpaper.service
```

### 3) Create a user timer

```bash
cp ./src/linux/bing-wallpaper.timer ~/.config/systemd/user/bing-wallpaper.timer
```

### 4) Enable the timer

```bash
systemctl --user daemon-reload
systemctl --user enable --now bing-wallpaper.timer
systemctl --user list-timers | grep bing
```

---

## Scheduling on macOS (launchd)

Use a LaunchAgent to run the script automatically **when the user logs in** (recommended).
You can also add an optional interval (every N hours) or a fixed daily time.

### 1) Put the script in a stable path

Example:

```bash
mkdir -p ~/.local/bin
cp ./src/bing-wallpaper.sh ~/.local/bin/bing-wallpaper.sh
chmod +x ~/.local/bin/bing-wallpaper.sh
```

### 2) Create the LaunchAgent

Create:

```text
~/Library/LaunchAgents/com.francisco.bing-wallpaper.plist
```

Content (runs on login):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>com.francisco.bing-wallpaper</string>

    <!-- Run automatically when the user logs in -->
    <key>RunAtLoad</key>
    <true/>

    <!-- Command to execute -->
    <key>ProgramArguments</key>
    <array>
      <string>/bin/bash</string>
      <string>-lc</string>
      <string>~/.local/bin/bing-wallpaper.sh -w -m pt-BR -r UHD</string>
    </array>

    <!-- Optional: also run every N seconds (example: every 6 hours = 21600) -->
    <!--
    <key>StartInterval</key>
    <integer>21600</integer>
    -->

    <!-- Optional: also run daily at a fixed time (example: 09:00) -->
    <!--
    <key>StartCalendarInterval</key>
    <dict>
      <key>Hour</key>
      <integer>9</integer>
      <key>Minute</key>
      <integer>0</integer>
    </dict>
    -->

    <key>StandardOutPath</key>
    <string>/tmp/bing-wallpaper.out.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/bing-wallpaper.err.log</string>
  </dict>
</plist>
```

### 3) Load / unload (enable / disable)

Load:

```bash
launchctl unload ~/Library/LaunchAgents/com.francisco.bing-wallpaper.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/com.francisco.bing-wallpaper.plist
```

Unload:

```bash
launchctl unload ~/Library/LaunchAgents/com.francisco.bing-wallpaper.plist
```

Verify:

```bash
launchctl list | grep com.francisco.bing-wallpaper || true
```

### 4) Debugging

```bash
tail -n 200 /tmp/bing-wallpaper.out.log
tail -n 200 /tmp/bing-wallpaper.err.log
```

---

## Notes

- Fedora KDE 43: `plasma-apply-wallpaperimage` is available by default and is the simplest KDE method.
- GNOME: the script uses `gsettings` and may behave slightly differently across GNOME versions.
- macOS: wallpaper is set via `osascript` and applies to all desktops/spaces.

---

## License

This repository is based on the upstream script.  
If you publish this as a separate repo, keep attribution to the original project and align licensing as appropriate.
