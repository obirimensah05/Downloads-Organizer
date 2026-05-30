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
#
# How it runs:
#   This script is the worker. It is invoked (via the OrganizeDownloads.app
#   AppleScript wrapper) by the launchd agent `local.organize-downloads`, which
#   watches `~/Downloads` for file-system changes (WatchPaths) and also sweeps
#   every 5 minutes (StartInterval) as a fallback. See install.sh and
#   com.organize-downloads.plist.template for how that agent is installed and
#   loaded. It is also safe to run by hand as a one-off sweep.
#
# Exit policy:
#   Every failure path exits 0 ("nothing to do" rather than "error"). This is
#   deliberate: launchd would otherwise treat a non-zero exit as a crash and
#   could throttle or flap the agent. The job is best-effort and idempotent.
#
# Note: rule definitions live inline below (the `move <Category> <globs>`
# block). The repo also ships a rules.conf describing a config-file format, but
# THIS script does not read it — see rules.conf for details.

# Fail on use of unset variables; do NOT abort on individual command errors
# (we want a single failing mv to skip one file, not kill the whole sweep).
set -u
# Restrict permissions on everything we create (category dirs, the lock dir):
# owner-only (0700 for dirs). Keeps a multi-user Mac from leaking file lists.
umask 077

DL="$HOME/Downloads"                                    # the folder we organize
LOCK_DIR="$HOME/Library/Caches/organize-downloads.lock" # single-instance lock
UID_ME="$(id -u)"                                       # current user's numeric UID

# log MESSAGE...
# Emit a timestamped, PID-tagged line to stdout. launchd redirects stdout to
# ~/Library/Logs/organize-downloads.log (and stderr to .err) per the plist.
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
# Single-instance lock. mkdir is atomic on every POSIX FS, so a successful
# mkdir of LOCK_DIR is the lock acquisition — only one process can win the race.
# A rapid burst of download events can fire launchd repeatedly; the lock keeps
# concurrent sweeps from fighting over the same files.
mkdir -p "$(dirname -- "$LOCK_DIR")" 2>/dev/null || true
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  # Lock already held. Treat a lock older than 600s as stale (a previous run
  # was killed before its EXIT trap could clean up) and forcibly reclaim it.
  lock_mtime="$(stat -f %m -- "$LOCK_DIR" 2>/dev/null || echo 0)"
  if [ "$(( $(date +%s) - lock_mtime ))" -gt 600 ]; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
    mkdir "$LOCK_DIR" 2>/dev/null || { log "abort: cannot acquire lock"; exit 0; }
  else
    log "skip: another run is in progress"
    exit 0
  fi
fi
# Release the lock on any exit (normal, error, or signal).
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

cd -- "$DL" || { log "abort: cd $DL failed"; exit 0; }

# ---------------------------------------------------------------------------
# Category subfolders, all living directly under ~/Downloads. Each is both a
# move destination AND "protected" — a category folder is never itself swept
# into Folders/ (see is_protected). To add a category: append it here and add a
# matching `move <Category> <globs>` line further down.
CATEGORIES=(Images Videos Spreadsheets Documents Archives PDFs HTML Calendar \
            Folders Audio Installers Code Design Fonts Ebooks WhatsApp Subtitles)
PROTECTED_DIRS=("${CATEGORIES[@]}")

# Pre-create each category folder (owner-only). A category that already exists
# as a symlink is left alone and flagged — we refuse to write through symlinks.
for c in "${CATEGORIES[@]}"; do
  if [ -L "$c" ]; then
    log "skip: $c is a symlink — refusing to use it (remove manually)"
    continue
  fi
  if [ ! -e "$c" ]; then
    mkdir -m 0700 -- "$c" || log "mkdir $c failed"
  fi
done

# dest_ok DIR
# True only if DIR is a safe move target: a real directory (not a symlink) that
# is owned by the current user. Guards against a planted symlink redirecting
# moves outside ~/Downloads, or a category dir owned by someone else.
dest_ok() {
  local d="$1"
  [ -L "$d" ] && return 1
  [ -d "$d" ] || return 1
  [ "$(stat -f %u -- "$d" 2>/dev/null)" = "$UID_ME" ] || return 1
  return 0
}

# is_protected NAME
# True if NAME is one of our category folders. Used to keep the stray-folder
# sweep from moving a category (e.g. Images/) into Folders/.
is_protected() {
  local name="$1"
  for p in "${PROTECTED_DIRS[@]}"; do
    [ "$name" = "$p" ] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# move DEST FILE...
# Move each FILE into category folder DEST (relative to ~/Downloads). FILE args
# are the result of glob expansion at the call site, so they are plain filenames
# in the current directory. Skips:
#   - a non-existent arg (an unmatched glob left literal — though nullglob below
#     usually prevents this),
#   - symlinks (defensively, never followed),
#   - anything that isn't a regular file,
#   - in-progress downloads (.crdownload/.part/.download/.tmp) and dotfiles.
# Uses `mv -n` (no-clobber); on a name collision in DEST, the file is renamed
# with a `dup_<epoch>_` prefix so nothing is ever overwritten or deleted.
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

# Make unmatched globs expand to nothing rather than to the literal pattern, so
# `move Images *.png` with no PNGs present passes zero args instead of "*.png".
# (bash uses `shopt -s nullglob`; the zsh fallback uses `setopt NULL_GLOB`.)
shopt -s nullglob 2>/dev/null || setopt NULL_GLOB 2>/dev/null

# --- Rules: each line maps a glob set to a category. First-listed wins for a
# given file because once moved it no longer matches later patterns. The
# WhatsApp prefix rule runs first so "WhatsApp Image ....jpg" lands in WhatsApp/
# rather than Images/.
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
# Stray-folder sweep: move any other top-level directory in ~/Downloads into
# Folders/, except the protected category folders themselves. Directory
# symlinks are skipped (never followed).
if dest_ok "Folders"; then
  for d in */; do
    name="${d%/}"
    is_protected "$name" && continue
    [ -L "$name" ] && { log "skip dir symlink: $name"; continue; }
    mtime="$(stat -f %m -- "$name" 2>/dev/null || echo 0)"
    [ "$mtime" -gt 0 ] || continue
    # Grace period: don't grab a folder modified in the last 5s — it may still
    # be mid-extraction (e.g. an unzipping archive) and not yet complete.
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
