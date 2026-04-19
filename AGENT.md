# Downloads Organizer — Agent Build Spec

Instructions for coding agents (Claude Code, OpenCode, Codex, etc.) to reproduce a macOS auto-organizer for `~/Downloads`. Target OS: macOS 12+. Shell: zsh/bash. No third-party deps.

## Goal

Automatically sort new files in `~/Downloads` into typed subfolders. Runs on file-system change (via `launchd` WatchPaths) and every 5 minutes as a safety net. Clickable `.app` also provided for manual runs.

## Deliverables

1. `~/bin/organize-downloads.sh` — the sorter script.
2. `~/Applications/OrganizeDownloads.app` — AppleScript applet wrapping the script (manual trigger + Dock icon).
3. `~/Library/LaunchAgents/local.organize-downloads.plist` — launchd agent for auto-run (rendered from `com.organize-downloads.plist.template`).
4. Log files at `~/Library/Logs/organize-downloads.log` and `.err`.

## Script behavior (`organize-downloads.sh`)

- `cd ~/Downloads`; create these subfolders if missing: `Images Videos Spreadsheets Documents Archives PDFs HTML Calendar Folders Audio Installers Code Design Fonts Ebooks WhatsApp Subtitles`.
- Skip in-progress downloads: `*.crdownload`, `*.part`, `*.download`, `*.tmp`, and dotfiles.
- On name collision, rename to `dup_<epoch>_<orig>` (never overwrite — use `mv -n`).
- **Order matters.** Process `WhatsApp *` (glob on filename prefix) BEFORE images/videos so WhatsApp media lands in `WhatsApp/` regardless of extension.
- Route by extension (case-insensitive where reasonable — include both `.jpg` and `.JPG` variants):
  - Images: png jpg jpeg webp gif heic
  - Videos: mp4 mov m4v avi mkv
  - Audio: mp3 wav m4a flac aac ogg opus
  - Spreadsheets: xlsx xls csv numbers tsv
  - PDFs: pdf
  - Documents: pptx ppt docx doc md txt rtf pages key
  - Installers: dmg pkg
  - Archives: zip rar 7z tar gz tgz
  - Code: json js ts py sh yaml yml toml xml
  - Design: psd ai sketch fig xd
  - Fonts: ttf otf woff woff2
  - Ebooks: epub mobi azw3
  - Subtitles: srt vtt
  - HTML: html htm
  - Calendar: ics
- After file routing, move any remaining top-level **directory** in `~/Downloads` into `Folders/`, except the protected org folders themselves. Skip directories modified in the last 5 seconds (archive may still be extracting).
- Use `shopt -s nullglob` (bash) or `setopt NULL_GLOB` (zsh) so empty globs don't error.
- Script must be idempotent and safe to run concurrently (rely on `mv -n`; no locking needed).

## launchd plist

- `Label`: `local.organize-downloads`
- `ProgramArguments`: `__HOME__/Applications/OrganizeDownloads.app/Contents/MacOS/applet` (so the AppleScript → shell chain runs with proper TCC prompts).
- `WatchPaths`: `["$HOME/Downloads"]` (substitute `__HOME__` at install time via `install.sh`)
- `ThrottleInterval`: `10` (seconds between triggers)
- `StartInterval`: `300` (5-minute fallback sweep)
- `StandardOutPath` / `StandardErrorPath`: `~/Library/Logs/organize-downloads.log` / `.err`
- Load with `launchctl bootstrap gui/$(id -u) <rendered-plist>`.

## AppleScript applet

Single line: `do shell script "$HOME/bin/organize-downloads.sh"` (resolved at install time). Save as Application via `osacompile -o ~/Applications/OrganizeDownloads.app`. User grants Full Disk Access or at minimum Downloads folder access on first run.

## Verification steps for the agent

1. `chmod +x ~/bin/organize-downloads.sh` and run it once manually; confirm no errors on an empty `~/Downloads`.
2. Drop a test `.png`, `.pdf`, `WhatsApp Image 2025.jpg`, and a dummy folder into `~/Downloads`; rerun; confirm each lands in the right subfolder.
3. Bootstrap the launch agent; `launchctl print gui/$(id -u)/local.organize-downloads` should show `state = running` or `waiting`.
4. Add a file to `~/Downloads`; within ~10s, log should record the run.
5. `open ~/Applications/OrganizeDownloads.app` triggers the sort manually.

## Constraints

- Do NOT delete files, ever. Only move.
- Do NOT touch files matching in-progress-download patterns or dotfiles.
- Do NOT recurse into existing subfolders; operate only on the top level of `~/Downloads`.
- Do not hardcode any username anywhere — use `$HOME`, `$USER`, or the `__HOME__` / `__LABEL__` placeholders substituted by `install.sh`.

## Reference implementation

See `organize-downloads.sh` in this repo for a working copy. Match its ordering and dup-handling exactly — both matter.
