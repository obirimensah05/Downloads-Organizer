# Downloads Organizer

Tiny macOS utility that sorts new files in `~/Downloads` into typed subfolders
(`Images/`, `PDFs/`, `Videos/`, `Archives/`, `WhatsApp/`, etc.) as they land.
Runs on file-system change via launchd, with a 5-minute fallback sweep.
Nothing is deleted — collisions are renamed `dup_<epoch>_<orig>`.

## Install

```bash
git clone <this-repo> ~/Downloads-Organizer    # clone anywhere — install.sh is portable
cd ~/Downloads-Organizer
chmod +x install.sh
./install.sh install
```

`install.sh` will:
- Copy `organize-downloads.sh` to `~/bin/` (0700).
- Compile a wrapper app at `~/Applications/OrganizeDownloads.app` via
  `osacompile` (so macOS permission prompts say "OrganizeDownloads", not
  "osascript").
- Render the launchd plist into `~/Library/LaunchAgents/local.organize-downloads.plist`
  with your actual `$HOME` substituted.
- `launchctl bootstrap` the agent.

## First-run permissions

macOS will prompt for **Files and Folders → Downloads** access the first time
the agent or app runs. Grant it. If no prompt appears, open
**System Settings → Privacy & Security → Files and Folders**, find
`OrganizeDownloads`, and enable **Downloads Folder**.

## Use

Drop files in `~/Downloads`. They move into the matching subfolder within ~10
seconds.

Manual sweep:
```bash
./install.sh run              # or open the Dock/Spotlight entry for OrganizeDownloads
```

Check it's running:
```bash
./install.sh status
tail -f ~/Library/Logs/organize-downloads.log
```

## Customize categories

Edit `organize-downloads.sh`. Each `move <Folder> *.ext` line is a rule — add,
remove, or rename freely. Also update the `CATEGORIES=(...)` list at the top so
the folder is auto-created and protected from being moved into itself.

After editing, reinstall so `~/bin/organize-downloads.sh` picks up the change:
```bash
./install.sh install
```

## Uninstall

```bash
./install.sh uninstall
```

Your files stay exactly where they landed. Delete the empty subfolders in
`~/Downloads` manually if you don't want them.

## What it never does

- **Never deletes.** Only `mv -n` with a `dup_<epoch>_` prefix on collision.
- **Never touches in-progress downloads** (`.crdownload`, `.part`, `.download`,
  `.tmp`) or dotfiles.
- **Never follows symlinks** — symlinked source files or category folders are
  skipped defensively. See `SECURITY.md` for the full threat model.
- **Never runs as root.** User agent only.

## For AI coding agents

See `AGENTS.md` for install-from-scratch steps, and `AGENT.md` for the full
script spec if you want to rebuild the sorter rather than just install it.
