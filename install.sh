#!/usr/bin/env bash
# Install/uninstall the Downloads Organizer launchd agent + AppleScript applet.
# Portable: detects the repo path it was run from, templates paths into the
# launchd plist, compiles the .app wrapper with osacompile, and loads launchd.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
LABEL="local.organize-downloads"
DEST_DIR="$HOME/Library/LaunchAgents"
DEST="$DEST_DIR/$LABEL.plist"
TEMPLATE="$REPO/com.organize-downloads.plist.template"

BIN="$HOME/bin/organize-downloads.sh"
APP="$HOME/Applications/OrganizeDownloads.app"

render_plist() {
  sed \
    -e "s|__LABEL__|$LABEL|g" \
    -e "s|__HOME__|$HOME|g" \
    -e "s|__REPO__|$REPO|g" \
    "$TEMPLATE"
}

case "${1:-install}" in
  install)
    [ -f "$TEMPLATE" ] || { echo "missing template: $TEMPLATE"; exit 1; }
    [ -f "$REPO/organize-downloads.sh" ] || { echo "missing: $REPO/organize-downloads.sh"; exit 1; }

    mkdir -p "$HOME/bin" "$HOME/Applications" "$DEST_DIR" "$HOME/Library/Logs"
    chmod 0700 "$HOME/bin" 2>/dev/null || true

    cp "$REPO/organize-downloads.sh" "$BIN"
    chmod 0700 "$BIN"

    # Compile a tiny AppleScript applet that wraps the shell script. The .app
    # wrapper exists so macOS can attribute Full Disk / Downloads-folder access
    # to "OrganizeDownloads" instead of "osascript".
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT
    cat >"$tmpdir/OrganizeDownloads.applescript" <<EOF
do shell script "$BIN"
EOF
    rm -rf "$APP"
    osacompile -o "$APP" "$tmpdir/OrganizeDownloads.applescript"

    render_plist >"$DEST"
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$DEST"
    echo "loaded $LABEL"
    echo
    echo "on first run macOS may prompt for access to your Downloads folder."
    echo "grant it in System Settings -> Privacy & Security -> Files and Folders."
    echo "logs: ~/Library/Logs/organize-downloads.log  /  .err"
    ;;
  uninstall)
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$DEST" "$BIN"
    rm -rf "$APP"
    echo "uninstalled $LABEL (the Downloads folder and its subfolders are left untouched)"
    ;;
  status)
    launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | head -5 || echo "not running"
    ;;
  run)
    # One-off manual sweep.
    exec "$BIN"
    ;;
  *)
    echo "usage: $0 {install|uninstall|status|run}"
    exit 1
    ;;
esac
