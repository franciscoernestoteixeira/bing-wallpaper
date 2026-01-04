# bing-wallpaper

A simple, cross-platform shell script that downloads Bing’s daily wallpaper and optionally sets it as your desktop background.

Based on the original project:  
https://github.com/thejandroman/bing-wallpaper

## Supported environments

- Fedora (KDE Plasma)
- Debian / Ubuntu (KDE Plasma or GNOME)
- macOS

---

## How it works

- Fetches Bing’s “image of the day” metadata (XML)
- Downloads the image in the chosen resolution
- Saves it under a local folder (default: `~/Pictures/bing-wallpapers`)
- Optionally sets it as your wallpaper depending on the detected desktop environment:
  - **KDE Plasma (desktop)**: `plasma-apply-wallpaperimage`
  - **KDE Plasma (lock screen, user-level)**: `kwriteconfig5` / `kwriteconfig6`
  - **GNOME**: `gsettings`
  - **macOS**: `osascript`

All operations run strictly at **user level**.  
No `sudo`, no system-wide configuration, no login-screen modification.

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

-w, --set-wallpaper          Set the downloaded image as desktop wallpaper

-L, --set-lockscreen         Also set KDE lock screen background (user-level)

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
./src/bing-wallpaper.sh -w -L -m pt-BR -r UHD
```

This will:

1. Download Bing’s image of the day
2. Save it locally
3. Set it as the desktop wallpaper
4. Set the KDE lock screen wallpaper (if running KDE and `-L` is used)

---

## Bing market codes (locales)

Bing supports many regional markets such as `en-US`, `pt-BR`, `en-GB`, etc.

Official list:  
https://github.com/MicrosoftDocs/bing-docs/blob/main/bing-docs/bing-web-search/reference/market-codes.md

---

## Scheduling on Linux (Fedora KDE / Debian / Ubuntu)

If your distro uses **systemd**, the recommended approach is a **user service + user timer**.

### 1) Copy the script to a stable path

```bash
mkdir -p ~/.local/bin
cp ./src/bing-wallpaper.sh ~/.local/bin/bing-wallpaper.sh
chmod +x ~/.local/bin/bing-wallpaper.sh
```

### 2) Copy the user service

```bash
mkdir -p ~/.config/systemd/user
cp ./src/linux/bing-wallpaper.service ~/.config/systemd/user/bing-wallpaper.service
```

### 3) Copy the user timer

```bash
mkdir -p ~/.config/systemd/user
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

Use a **LaunchAgent** to run the script automatically when the user logs in, or on a schedule.

### 1) Put the script in a stable path

```bash
mkdir -p ~/.local/bin
cp ./src/bing-wallpaper.sh ~/.local/bin/bing-wallpaper.sh
chmod +x ~/.local/bin/bing-wallpaper.sh
```

### 2) Create the LaunchAgent

Create:

```
~/Library/LaunchAgents/com.francisco.bing-wallpaper.plist
```

Content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>com.francisco.bing-wallpaper</string>

    <key>RunAtLoad</key>
    <true/>

    <key>ProgramArguments</key>
    <array>
      <string>/bin/bash</string>
      <string>-lc</string>
      <string>~/.local/bin/bing-wallpaper.sh -w -m pt-BR -r UHD</string>
    </array>

    <key>StandardOutPath</key>
    <string>/tmp/bing-wallpaper.out.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/bing-wallpaper.err.log</string>
  </dict>
</plist>
```

Load it:

```bash
launchctl load ~/Library/LaunchAgents/com.francisco.bing-wallpaper.plist
```

Verify:

```bash
launchctl list | grep com.francisco.bing-wallpaper || true
```

---

## Notes

- **KDE Plasma**: `plasma-apply-wallpaperimage` is the cleanest and fastest solution.
- **KDE lock screen** changes are written to `~/.config/kscreenlockerrc` only.
- **GNOME** behavior may vary slightly across versions.
- **macOS** wallpaper is applied to all desktops/spaces.

---

## License

This project is based on the upstream script.  
If published as a separate repository, keep attribution to the original project and align licensing accordingly.
