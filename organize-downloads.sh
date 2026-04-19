#!/bin/bash
# Organizes ~/Downloads by file type. Hardened version.
#
# Security properties:
#  - All user-controlled filenames are passed after `--` so a name like
#    `-rf` or `-i` can't be interpreted as an option flag by mv / stat / test.
#  - Category destination directories must be real, user-owned, non-symlink
#    directories. A symlinked `~/Downloads/Images` does NOT redirect files.
#  - Source symlinks are skipped, not shuffled into category folders.
#  - A mkdir-based lock prevents two launchd-triggered runs from racing.
#  - umask 077 on every file/dir the script creates.
#  - Abort if ~/Downloads is missing, a symlink, or not owned by this user.
#
# Never deletes. Uses `mv -n` exclusively; on collision, renames with a
# `dup_<epoch>_` prefix.

set -u
umask 077

DL="$HOME/Downloads"
LOCK_DIR="$HOME/Library/Caches/organize-downloads.lock"
UID_ME="$(id -u)"

log() {
  printf '%s [organize-downloads %d] %s\n' \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$$" "$*"
}

# ---------------------------------------------------------------------------
# Pre-flight safety checks on ~/Downloads.
if [ -L "$DL" ] || [ ! -d "$DL" ]; then
  log "abort: \$DL ($DL) is missing or is a symlink"
  exit 0
fi
if [ "$(stat -f %u -- "$DL" 2>/dev/null)" != "$UID_ME" ]; then
  log "abort: \$DL not owned by current user"
  exit 0
fi

# ---------------------------------------------------------------------------
# Single-instance lock. mkdir is atomic on every POSIX FS.
mkdir -p "$(dirname -- "$LOCK_DIR")" 2>/dev/null || true
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  lock_mtime="$(stat -f %m -- "$LOCK_DIR" 2>/dev/null || echo 0)"
  if [ "$(( $(date +%s) - lock_mtime ))" -gt 600 ]; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
    mkdir "$LOCK_DIR" 2>/dev/null || { log "abort: cannot acquire lock"; exit 0; }
  else
    log "skip: another run is in progress"
    exit 0
  fi
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

cd -- "$DL" || { log "abort: cd $DL failed"; exit 0; }

# ---------------------------------------------------------------------------
CATEGORIES=(Images Videos Spreadsheets Documents Archives PDFs HTML Calendar \
            Folders Audio Installers Code Design Fonts Ebooks WhatsApp Subtitles)
PROTECTED_DIRS=("${CATEGORIES[@]}")

for c in "${CATEGORIES[@]}"; do
  if [ -L "$c" ]; then
    log "skip: $c is a symlink — refusing to use it (remove manually)"
    continue
  fi
  if [ ! -e "$c" ]; then
    mkdir -m 0700 -- "$c" || log "mkdir $c failed"
  fi
done

dest_ok() {
  local d="$1"
  [ -L "$d" ] && return 1
  [ -d "$d" ] || return 1
  [ "$(stat -f %u -- "$d" 2>/dev/null)" = "$UID_ME" ] || return 1
  return 0
}

is_protected() {
  local name="$1"
  for p in "${PROTECTED_DIRS[@]}"; do
    [ "$name" = "$p" ] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
move() {
  local dest="$1"; shift
  if ! dest_ok "$dest"; then
    log "skip category: $dest not a safe destination"
    return
  fi
  for f in "$@"; do
    [ -e "$f" ] || continue
    [ -L "$f" ] && { log "skip symlink: $f"; continue; }
    [ -f "$f" ] || continue
    case "$f" in
      *.crdownload|*.part|*.download|*.tmp|.*) continue ;;
    esac
    if [ -e "$dest/$f" ]; then
      mv -n -- "$f" "$dest/dup_$(date +%s)_$f" \
        && log "moved (dup): $f -> $dest/"
    else
      mv -n -- "$f" "$dest/" \
        && log "moved: $f -> $dest/"
    fi
  done
}

shopt -s nullglob 2>/dev/null || setopt NULL_GLOB 2>/dev/null

move WhatsApp     WhatsApp\ *

move Images       *.png *.jpg *.jpeg *.webp *.gif *.heic *.PNG *.JPG *.JPEG *.WEBP *.GIF *.HEIC
move Videos       *.mp4 *.mov *.m4v *.avi *.mkv *.MP4 *.MOV *.M4V *.AVI *.MKV
move Audio        *.mp3 *.wav *.m4a *.flac *.aac *.ogg *.opus *.MP3 *.WAV *.M4A
move Spreadsheets *.xlsx *.xls *.csv *.numbers *.tsv *.XLSX *.XLS *.CSV
move PDFs         *.pdf *.PDF
move Documents    *.pptx *.ppt *.docx *.doc *.md *.txt *.rtf *.pages *.key
move Installers   *.dmg *.pkg *.DMG *.PKG
move Archives     *.zip *.rar *.7z *.tar *.gz *.tgz *.ZIP
move Code         *.json *.js *.ts *.py *.sh *.yaml *.yml *.toml *.xml
move Design       *.psd *.ai *.sketch *.fig *.xd
move Fonts        *.ttf *.otf *.woff *.woff2
move Ebooks       *.epub *.mobi *.azw3
move Subtitles    *.srt *.vtt
move HTML         *.html *.htm
move Calendar     *.ics

# ---------------------------------------------------------------------------
# Move any other top-level folder into Folders/, except protected ones.
if dest_ok "Folders"; then
  for d in */; do
    name="${d%/}"
    is_protected "$name" && continue
    [ -L "$name" ] && { log "skip dir symlink: $name"; continue; }
    mtime="$(stat -f %m -- "$name" 2>/dev/null || echo 0)"
    [ "$mtime" -gt 0 ] || continue
    if [ "$(( $(date +%s) - mtime ))" -lt 5 ]; then
      continue
    fi
    if [ -e "Folders/$name" ]; then
      mv -n -- "$name" "Folders/dup_$(date +%s)_$name" \
        && log "moved dir (dup): $name -> Folders/"
    else
      mv -n -- "$name" "Folders/" \
        && log "moved dir: $name -> Folders/"
    fi
  done
else
  log "skip: Folders/ not a safe destination"
fi
