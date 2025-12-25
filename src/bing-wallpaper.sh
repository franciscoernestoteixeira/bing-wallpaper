#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Bing wallpaper downloader + wallpaper setter for:
# - macOS (osascript / System Events)
# - KDE Plasma (desktop: plasma-apply-wallpaperimage)
# - KDE Lock Screen (kwriteconfig5/6 -> kscreenlockerrc)
# - KDE Login Screen (SDDM Breeze via /var/lib/sddm/themes/breeze/theme.conf.user) [root]
# - GNOME (gsettings) [desktop + lock screen]
#
# Base deps: curl, sed, tr, head, mkdir
# KDE deps:  plasma-apply-wallpaperimage, kwriteconfig5|kwriteconfig6 (for lock screen)
# GNOME deps: gsettings
# macOS deps: osascript
#
# Notes:
# - KDE Login Screen changes require root (sudo) and assume SDDM + Breeze theme. :contentReference[oaicite:3]{index=3}
# - GNOME GDM login background changes are intentionally not standardized and can break on updates.
# -----------------------------------------------------------------------------

PICTURE_DIR_DEFAULT="${HOME}/Pictures/bing-wallpapers"
MKT_DEFAULT="en-US"          # Bing market/locale (e.g., pt-BR, en-US, en-GB)
RESOLUTION_DEFAULT="UHD"     # UHD, 1920x1200, 1920x1080, 800x480, 400x240

QUIET=0
FORCE=0
SET_WALLPAPER=0
SET_LOCKSCREEN=0
SET_LOGIN=0

PICTURE_DIR="${PICTURE_DIR_DEFAULT}"
MKT="${MKT_DEFAULT}"
RESOLUTION="${RESOLUTION_DEFAULT}"

# Internal: used only when the script re-enters as root to apply login wallpaper.
APPLY_LOGIN_ONLY=0
APPLY_LOGIN_FILE=""

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
  -r, --resolution <res>       UHD|1920x1200|1920x1080|800x480|400x240 (default: ${RESOLUTION_DEFAULT})
  -w, --set-wallpaper          Set downloaded image as desktop wallpaper
  -L, --set-lockscreen         Also set lock screen background (KDE only)
  -S, --set-login              Also set login screen background (KDE + SDDM theme; requires sudo/root)
  -f, --force                  Force re-download even if file exists
  -q, --quiet                  Less output
  -h, --help                   Show help

Examples:
  $(basename "$0") -w
  $(basename "$0") -w -L
  $(basename "$0") -w -L -S -m pt-BR -r UHD
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
      -S|--set-login)   SET_LOGIN=1; shift;;
      -f|--force)       FORCE=1; shift;;
      -q|--quiet)       QUIET=1; shift;;
      -h|--help)        usage; exit 0;;

      # Internal: apply ONLY login wallpaper as root for the given file.
      --_apply-login)
        APPLY_LOGIN_ONLY=1
        APPLY_LOGIN_FILE="$2"
        shift 2
        ;;

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

  local startdate url urlBase
  startdate="$(parse_xml_tag "$xml" "startdate")"
  url="$(parse_xml_tag "$xml" "url")"
  urlBase="$(parse_xml_tag "$xml" "urlBase")"

  [[ -n "${startdate}" ]] || die "Could not parse <startdate> from Bing feed"
  [[ -n "${url}" ]] || die "Could not parse <url> from Bing feed"

  # Prefer a URL that matches the requested resolution when urlBase is available.
  local final_url="https://www.bing.com${url}"
  if [[ -n "${urlBase}" ]]; then
    case "${RESOLUTION}" in
      UHD)         final_url="https://www.bing.com${urlBase}_UHD.jpg";;
      1920x1200)   final_url="https://www.bing.com${urlBase}_1920x1200.jpg";;
      1920x1080)   final_url="https://www.bing.com${urlBase}_1920x1080.jpg";;
      800x480)     final_url="https://www.bing.com${urlBase}_800x480.jpg";;
      400x240)     final_url="https://www.bing.com${urlBase}_400x240.jpg";;
      *) die "Unsupported resolution: ${RESOLUTION}";;
    esac
  else
    log "No <urlBase> found; falling back to <url> as-is."
  fi

  local filename="${startdate}-${MKT}-${RESOLUTION}.jpg"
  local out="${PICTURE_DIR}/${filename}"

  if [[ -f "${out}" && "${FORCE}" -eq 0 ]]; then
    log "Already downloaded: ${out}"
    echo "${out}"
    return 0
  fi

  log "Downloading: ${final_url}"
  curl -fL --retry 3 --retry-delay 1 -o "${out}" "${final_url}" || die "Download failed"
  log "Saved: ${out}"
  echo "${out}"
}

set_wallpaper_macos() {
  local file="$1"
  have osascript || die "osascript not found (required on macOS)"

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
  local file="$1"
  have plasma-apply-wallpaperimage || die "plasma-apply-wallpaperimage not found"
  log "KDE: setting desktop wallpaper"
  plasma-apply-wallpaperimage "${file}" >/dev/null 2>&1 || die "Failed to set KDE wallpaper"
}

set_wallpaper_kde_lockscreen() {
  local file="$1"
  local kw=""
  if have kwriteconfig6; then kw="kwriteconfig6"
  elif have kwriteconfig5; then kw="kwriteconfig5"
  else die "kwriteconfig5/kwriteconfig6 not found (needed to set KDE lock screen wallpaper)"
  fi

  # Writes KDE lock screen background into kscreenlockerrc. :contentReference[oaicite:4]{index=4}
  log "KDE: setting lock screen wallpaper"
  "${kw}" --file kscreenlockerrc \
    --group Greeter \
    --group Wallpaper \
    --group org.kde.image \
    --group General \
    --key Image "file://${file}" || die "Failed to write kscreenlockerrc"
}

# -----------------------------------------------------------------------------
# SDDM helpers (Fedora typically uses /usr/share/sddm/themes; theme might not be "breeze")
#
# This keeps the same "Breeze theme.conf.user" approach, but:
# - Detects current theme from /etc/sddm.conf and /etc/sddm.conf.d/*.conf
# - Detects ThemeDir if set (some distros allow overriding theme directory)
# - Falls back to common theme roots
# -----------------------------------------------------------------------------

sddm_conf_files() {
  # SDDM reads /etc/sddm.conf and then /etc/sddm.conf.d/*.conf.
  # We gather both and parse them in order.
  local files=()
  [[ -f /etc/sddm.conf ]] && files+=("/etc/sddm.conf")
  if compgen -G "/etc/sddm.conf.d/*.conf" >/dev/null; then
    # shellcheck disable=SC2206
    files+=(/etc/sddm.conf.d/*.conf)
  fi
  printf '%s\n' "${files[@]}"
}

sddm_get_value() {
  # Read a key from [Theme] section (best-effort; last occurrence wins).
  # Usage: sddm_get_value "Current" or "ThemeDir"
  local key="$1"
  local value=""

  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    # Extract only lines between [Theme] and next section header.
    # Then pick key=value and keep last match.
    local v
    v="$(sed -n '/^\[Theme\]/,/^\[/{p}' "$f" | sed -n "s/^${key}[[:space:]]*=[[:space:]]*//p" | tail -n 1 || true)"
    [[ -n "${v}" ]] && value="${v}"
  done < <(sddm_conf_files)

  echo "${value}"
}

sddm_theme_dir_candidates() {
  # ThemeDir can override the base dir; otherwise default is typically /usr/share/sddm/themes.
  local theme_dir
  theme_dir="$(sddm_get_value "ThemeDir")"

  if [[ -n "${theme_dir}" ]]; then
    echo "${theme_dir}"
  fi

  # Common defaults across distros:
  echo "/usr/share/sddm/themes"
  echo "/usr/local/share/sddm/themes"
  echo "/var/lib/sddm/themes"
  echo "/var/sddm/themes"
}

sddm_current_theme_name() {
  local current
  current="$(sddm_get_value "Current")"
  if [[ -n "${current}" ]]; then
    echo "${current}"
    return 0
  fi

  # If not configured, many KDE setups default to "breeze".
  echo "breeze"
}

sddm_find_theme_dir() {
  # Find the active theme directory based on configuration + common paths.
  local theme
  theme="$(sddm_current_theme_name)"

  while IFS= read -r base; do
    [[ -n "${base}" ]] || continue
    if [[ -d "${base}/${theme}" ]]; then
      echo "${base}/${theme}"
      return 0
    fi
  done < <(sddm_theme_dir_candidates)

  # Fedora/KDE may ship Breeze as breeze or breeze6 depending on Plasma/Qt version.
  # If Current=breeze but only breeze6 exists, fall back.
  if [[ "${theme}" == "breeze" ]]; then
    while IFS= read -r base; do
      [[ -n "${base}" ]] || continue
      if [[ -d "${base}/breeze6" ]]; then
        echo "${base}/breeze6"
        return 0
      fi
    done < <(sddm_theme_dir_candidates)
  fi

  return 1
}

set_wallpaper_kde_login_sddm_breeze() {
  local file="$1"

  # Requires root: writes into SDDM theme directory and theme.conf.user. :contentReference[oaicite:5]{index=5}
  if [[ "$(id -u)" -ne 0 ]]; then
    die "KDE login wallpaper requires root. Re-run with sudo: sudo $0 ... -S"
  fi

  have install || die "install is required"

  local theme_dir=""
  if ! theme_dir="$(sddm_find_theme_dir)"; then
    die "SDDM theme directory not found. Checked ThemeDir/Current in /etc/sddm.conf* and common locations."
  fi

  log "SDDM: using theme dir: ${theme_dir}"

  log "SDDM: copying image into ${theme_dir}"
  install -m 0644 "${file}" "${theme_dir}/bing-login-background.jpg"

  # Many themes (including Breeze) allow overrides via theme.conf.user.
  # If your theme ignores theme.conf.user, you may need to edit theme.conf or use a theme-specific key.
  log "SDDM: writing ${theme_dir}/theme.conf.user"
  cat > "${theme_dir}/theme.conf.user" <<EOF
[General]
type=image
background=bing-login-background.jpg
EOF
}

set_wallpaper_gnome() {
  local file="$1"
  have gsettings || die "gsettings not found (GNOME required)"

  # GNOME expects file:// URIs.
  local uri="file://${file}"

  # Best-effort: picture-uri is standard; picture-uri-dark exists on newer GNOME.
  log "GNOME: setting desktop wallpaper"
  gsettings set org.gnome.desktop.background picture-uri "${uri}" || true
  gsettings set org.gnome.desktop.background picture-uri-dark "${uri}" 2>/dev/null || true

  # GNOME lock screen typically follows the same background; no separate stable API is guaranteed across versions.
}

detect_desktop() {
  # Best-effort desktop detection.
  local xdg="${XDG_CURRENT_DESKTOP:-}"
  local session="${DESKTOP_SESSION:-}"
  local kde="${KDE_FULL_SESSION:-}"

  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "macos"; return
  fi
  if [[ -n "${kde}" ]] || [[ "${xdg}" =~ KDE|Plasma ]] || [[ "${session}" =~ plasma|kde ]]; then
    echo "kde"; return
  fi
  if [[ "${xdg}" =~ GNOME ]] || [[ "${session}" =~ gnome ]]; then
    echo "gnome"; return
  fi

  # Best-effort fallback: if Plasma helper exists, assume KDE.
  if have plasma-apply-wallpaperimage; then
    echo "kde"; return
  fi

  echo "unknown"
}

apply_login_with_sudo_if_needed() {
  local file="$1"

  # KDE Login Screen changes require root (sudo). Try to do it automatically for newbie users.
  if [[ "$(id -u)" -eq 0 ]]; then
    set_wallpaper_kde_login_sddm_breeze "${file}"
    return 0
  fi

  have sudo || die "sudo not found (required for -S / --set-login)"

  log "KDE: login wallpaper needs admin permissions; requesting sudo..."
  sudo -E "$0" --_apply-login "${file}"
}

main() {
  parse_args "$@"

  # Internal mode: apply ONLY the login wallpaper as root, then exit.
  if [[ "${APPLY_LOGIN_ONLY}" -eq 1 ]]; then
    [[ -n "${APPLY_LOGIN_FILE}" ]] || die "Missing file for --_apply-login"
    set_wallpaper_kde_login_sddm_breeze "${APPLY_LOGIN_FILE}"
    log "Done."
    return 0
  fi

  local file
  file="$(download_bing_image)"

  if [[ "${SET_WALLPAPER}" -eq 0 && "${SET_LOCKSCREEN}" -eq 0 && "${SET_LOGIN}" -eq 0 ]]; then
    log "Done (download only). Use -w/-L/-S to apply."
    return 0
  fi

  local desktop
  desktop="$(detect_desktop)"
  log "Detected desktop: ${desktop}"

  case "${desktop}" in
    macos)
      [[ "${SET_WALLPAPER}" -eq 1 ]] && set_wallpaper_macos "${file}"
      # macOS “system login screen background” is not reliably configurable on modern versions without security tradeoffs. :contentReference[oaicite:6]{index=6}
      if [[ "${SET_LOGIN}" -eq 1 ]]; then
        log "macOS: login window wallpaper is not handled here."
      fi
      ;;
    kde)
      [[ "${SET_WALLPAPER}" -eq 1 ]] && set_wallpaper_kde_desktop "${file}"
      [[ "${SET_LOCKSCREEN}" -eq 1 ]] && set_wallpaper_kde_lockscreen "${file}"
      [[ "${SET_LOGIN}" -eq 1 ]] && apply_login_with_sudo_if_needed "${file}"
      ;;
    gnome)
      [[ "${SET_WALLPAPER}" -eq 1 ]] && set_wallpaper_gnome "${file}"
      if [[ "${SET_LOCKSCREEN}" -eq 1 ]]; then
        log "GNOME: lock screen is generally tied to the same background; no separate stable method applied."
      fi
      if [[ "${SET_LOGIN}" -eq 1 ]]; then
        die "GNOME GDM login background is not handled here (fragile resource rebuild; varies by distro/GNOME version)."
      fi
      ;;
    *)
      die "Unsupported desktop. Download succeeded at: ${file}"
      ;;
  esac

  log "Done."
}

main "$@"
