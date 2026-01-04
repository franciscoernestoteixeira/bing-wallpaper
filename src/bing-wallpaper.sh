#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Bing wallpaper downloader + wallpaper setter for:
# - macOS (osascript / System Events)
# - KDE Plasma (desktop: plasma-apply-wallpaperimage)
# - KDE Lock Screen (kwriteconfig5/6 -> kscreenlockerrc) [user-level]
# - GNOME (gsettings) [desktop]
#
# Base deps: curl, sed, tr, head, mkdir
# KDE deps:  plasma-apply-wallpaperimage, kwriteconfig5|kwriteconfig6
# GNOME deps: gsettings
# macOS deps: osascript
# -----------------------------------------------------------------------------

PICTURE_DIR_DEFAULT="${HOME}/Pictures/bing-wallpapers"
MKT_DEFAULT="en-US"          # Bing market/locale (e.g., pt-BR, en-US, en-GB)
RESOLUTION_DEFAULT="UHD"     # UHD, 1920x1200, 1920x1080, 800x480, 400x240

QUIET=0
FORCE=0
SET_WALLPAPER=0
SET_LOCKSCREEN=0

PICTURE_DIR="${PICTURE_DIR_DEFAULT}"
MKT="${MKT_DEFAULT}"
RESOLUTION="${RESOLUTION_DEFAULT}"

log() { [[ "${QUIET}" -eq 0 ]] && echo "[bing-wallpaper] $*" >&2; }
die() { echo "[bing-wallpaper] ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [options]

Options:
  -p, --picturedir <dir>       Download directory (default: ${PICTURE_DIR_DEFAULT})
  -m, --market <mkt>           Bing market/locale (default: ${MKT_DEFAULT})
  -r, --resolution <res>       UHD|1920x1200|1920x1080|800x480|400x240
  -w, --set-wallpaper          Set downloaded image as desktop wallpaper
  -L, --set-lockscreen         Also set lock screen background (KDE only)
  -f, --force                  Force re-download even if file exists
  -q, --quiet                  Less output
  -h, --help                   Show help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--picturedir) PICTURE_DIR="$2"; shift 2;;
      -m|--market)     MKT="$2"; shift 2;;
      -r|--resolution) RESOLUTION="$2"; shift 2;;
      -w|--set-wallpaper) SET_WALLPAPER=1; shift;;
      -L|--set-lockscreen) SET_LOCKSCREEN=1; shift;;
      -f|--force)       FORCE=1; shift;;
      -q|--quiet)       QUIET=1; shift;;
      -h|--help)        usage; exit 0;;
      *) die "Unknown option: $1";;
    esac
  done
}

bing_feed_url() {
  # Bing image metadata endpoint (XML):
  # - idx=0 => today
  # - n=1   => one image
  # - mkt   => market/locale
  echo "https://www.bing.com/HPImageArchive.aspx?format=xml&idx=0&n=1&mkt=${MKT}"
}

parse_xml_tag() {
  # Extract a simple tag from XML (first match).
  # This keeps the script dependency-free (no xmlstarlet).
  # Usage: parse_xml_tag "<xml>" "url"
  local xml="$1"
  local tag="$2"
  echo "$xml" | tr -d '\n' | sed -n "s|.*<${tag}>\\(.*\\)</${tag}>.*|\\1|p" | head -n 1
}

download_bing_image() {
  have curl || die "curl is required"

  mkdir -p "${PICTURE_DIR}"

  log "Fetching Bing feed: $(bing_feed_url)"
  local xml
  xml="$(curl -fsSL "$(bing_feed_url)")"

  local startdate urlBase
  startdate="$(parse_xml_tag "$xml" "startdate")"
  urlBase="$(parse_xml_tag "$xml" "urlBase")"

  [[ -n "${startdate}" && -n "${urlBase}" ]] || die "Invalid Bing feed"

  # Prefer a URL that matches the requested resolution when urlBase is available.
  local final_url
  case "${RESOLUTION}" in
    UHD)         final_url="https://www.bing.com${urlBase}_UHD.jpg";;
    1920x1200)   final_url="https://www.bing.com${urlBase}_1920x1200.jpg";;
    1920x1080)   final_url="https://www.bing.com${urlBase}_1920x1080.jpg";;
    800x480)     final_url="https://www.bing.com${urlBase}_800x480.jpg";;
    400x240)     final_url="https://www.bing.com${urlBase}_400x240.jpg";;
    *) die "Unsupported resolution: ${RESOLUTION}";;
  esac

  local out="${PICTURE_DIR}/${startdate}-${MKT}-${RESOLUTION}.jpg"

  if [[ -f "${out}" && "${FORCE}" -eq 0 ]]; then
    log "Already downloaded: ${out}"
    echo "${out}"
    return
  fi

  log "Downloading: ${final_url}"
  curl -fL -o "${out}" "${final_url}" || die "Download failed"
  log "Saved: ${out}"
  echo "${out}"
}

set_wallpaper_macos() {
  local file="$1"
  have osascript || die "osascript not found"

  # Set the picture for all desktops/spaces.
  osascript <<OSA
tell application "System Events"
  repeat with d in desktops
    set picture of d to POSIX file "${file}"
  end repeat
end tell
OSA
}

set_wallpaper_kde_desktop() {
  have plasma-apply-wallpaperimage || die "plasma-apply-wallpaperimage not found"
  log "KDE: setting desktop wallpaper"
  plasma-apply-wallpaperimage "$1" >/dev/null
}

set_wallpaper_kde_lockscreen() {
  local kw
  if have kwriteconfig6; then kw=kwriteconfig6
  elif have kwriteconfig5; then kw=kwriteconfig5
  else die "kwriteconfig not found"
  fi

  # Writes KDE lock screen background into kscreenlockerrc. :contentReference[oaicite:4]{index=4}
  log "KDE: setting lock screen wallpaper"
  "${kw}" --file kscreenlockerrc \
    --group Greeter \
    --group Wallpaper \
    --group org.kde.image \
    --group General \
    --key Image "file://$1"
}

set_wallpaper_gnome() {
  # Best-effort: picture-uri is standard; picture-uri-dark exists on newer GNOME.
  log "GNOME: setting desktop wallpaper"
  have gsettings || die "gsettings not found"

  # GNOME expects file:// URIs.
  local uri="file://$1"
  gsettings set org.gnome.desktop.background picture-uri "${uri}" || true
  gsettings set org.gnome.desktop.background picture-uri-dark "${uri}" 2>/dev/null || true

  # GNOME lock screen typically follows the same background; no separate stable API is guaranteed across versions.
}

detect_desktop() {
  # Best-effort desktop detection.
  if [[ "$(uname -s)" == "Darwin" ]]; then echo "macos"; return; fi
  [[ "${XDG_CURRENT_DESKTOP:-}" =~ KDE|Plasma ]] && echo "kde" && return
  [[ "${XDG_CURRENT_DESKTOP:-}" =~ GNOME ]] && echo "gnome" && return
  have plasma-apply-wallpaperimage && echo "kde" && return
  echo "unknown"
}

main() {
  parse_args "$@"
  local file
  file="$(download_bing_image)"

  local desktop
  desktop="$(detect_desktop)"
  log "Detected desktop: ${desktop}"

  case "${desktop}" in
    macos)
      [[ "${SET_WALLPAPER}" -eq 1 ]] && set_wallpaper_macos "${file}"
      ;;
    kde)
      [[ "${SET_WALLPAPER}" -eq 1 ]] && set_wallpaper_kde_desktop "${file}"
      [[ "${SET_LOCKSCREEN}" -eq 1 ]] && set_wallpaper_kde_lockscreen "${file}"
      ;;
    gnome)
      [[ "${SET_WALLPAPER}" -eq 1 ]] && set_wallpaper_gnome "${file}"
      ;;
    *)
      die "Unsupported desktop. Download succeeded at: ${file}"
      ;;
  esac

  log "Done."
}

main "$@"
