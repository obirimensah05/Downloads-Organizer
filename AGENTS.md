# AGENTS.md — Downloads Organizer

Instructions for an AI coding agent to install this project on the user's Mac.
All paths derive from `$HOME` and the repo's own location; **never** hardcode
`/Users/<someone>/...`.

Target OS: macOS 11+. Shell: zsh/bash. No third-party deps.

## What you are installing

- A launchd agent labelled `local.organize-downloads` watching `~/Downloads`.
- `~/bin/organize-downloads.sh` — the sorter script.
- `~/Applications/OrganizeDownloads.app` — compiled AppleScript wrapper so
  permission prompts name "OrganizeDownloads" instead of "osascript".

## Preconditions to verify

1. The user is on macOS and has write access to `~/Library/LaunchAgents/`,
   `~/bin/`, and `~/Applications/`.
2. The repo is already a working copy at some absolute path — let
   `REPO=$(pwd)` after `cd`-ing into it.
3. `osacompile` and `launchctl` are on `PATH` (both ship with macOS).

## Install (happy path)

```bash
cd <path-to-this-repo>
chmod +x ./install.sh
./install.sh install
```

`install.sh` will:
1. Copy `organize-downloads.sh` → `~/bin/organize-downloads.sh` (0700).
2. `osacompile` a one-line AppleScript into
   `~/Applications/OrganizeDownloads.app` that runs the shell script.
3. Render `com.organize-downloads.plist.template` into
   `~/Library/LaunchAgents/local.organize-downloads.plist`, substituting
   `__LABEL__` / `__HOME__` / `__REPO__`.
4. `launchctl bootstrap gui/$(id -u)` the plist.

## Verify the install

```bash
./install.sh status                   # should not print "not running"
./install.sh run                      # one-off manual sweep
ls ~/Downloads                        # category subfolders now exist
tail ~/Library/Logs/organize-downloads.log
```

Drop a test file (any `.pdf` / `.png`) into `~/Downloads` and watch the log —
the file should move into the matching subfolder within ~10s.

## Permission prompt walkthrough (tell the user)

First touch of `~/Downloads` triggers macOS's file-access prompt attributed to
"OrganizeDownloads". If the user dismisses it, guide them to
**System Settings → Privacy & Security → Files and Folders → OrganizeDownloads →
Downloads Folder: ON**.

## Uninstall

```bash
./install.sh uninstall
```

Removes the launchd agent, the plist, `~/bin/organize-downloads.sh`, and the
`.app` wrapper. The user's `~/Downloads` folder and its contents are untouched.

## Do NOT

- Do **not** bake any `/Users/<someone>/...` path into a committed file. Use
  `$HOME`, `$(pwd)`, or the `__HOME__` / `__REPO__` placeholders.
- Do **not** delete files. The script uses `mv -n` exclusively; adding any
  `rm` would be a regression (tested for in `SECURITY.md`).
- Do **not** follow symlinks — see `dest_ok()` and `[ -L "$f" ]` guards in
  the script.
- Do **not** commit `~/Library/Logs/organize-downloads.*`; they're not in the
  repo, and `.DS_Store` is gitignored.

## Reference

- `AGENT.md` — full build spec (rebuild from scratch without using the
  reference implementation). Use for behavior questions.
- `SOP.md` — human-facing setup guide. Useful to paraphrase for the user.
- `SECURITY.md` — threat model, mitigations, verification script.
- `organize-downloads.sh` — reference implementation. Match its ordering and
  dup-handling exactly if you rewrite it.
