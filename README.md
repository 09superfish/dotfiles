# Dotfiles

My personal Hyprland dotfiles for Fedora Linux. Configs are managed with symlinks so any changes made to the files are automatically tracked by git.

## What's included

| config | what it is |
|---|---|
| `fastfetch` | system info fetch tool |
| `hypr` | Hyprland window manager + all modules |
| `kicad` | PCB drawing tool |
| `kitty` | terminal emulator |
| `supertuxkart` | game controls |
| `swaync` | notification center |
| `waybar` | status bar |
| `wofi` | app launcher |

## Fresh install

Make sure `git` is installed, then:

```bash
# download the script
curl -o ~/symlink-dotfiles.sh https://raw.githubusercontent.com/09superfish/dotfiles/main/symlink-dotfiles.sh

# run it (sudo needed only the first time to install the script to /bin)
sudo bash ~/symlink-dotfiles.sh
```

On first run the script will:
- Clone the repo into `~/.dotfiles`
- Create `~/.dotfiles/.backup` for any pre-existing configs
- Install itself to `/bin/symlink-dotfiles` so you can run it from anywhere
- Auto-detect and symlink every folder in `.dotfiles/.config` into `~/.config`, backing up anything already there with a timestamp

After the first run, just call `symlink-dotfiles` from anywhere to pull the latest changes and re-link everything.

## Usage

```
symlink-dotfiles [flag] [config]
```

Most flags accept an optional `[config]` argument to target a single config instead of all of them.

| command | description |
|---|---|
| `symlink-dotfiles` | pull latest + re-link all configs |
| `symlink-dotfiles waybar` | pull latest + re-link waybar only |
| `symlink-dotfiles --status` | show link state of all configs |
| `symlink-dotfiles --status waybar` | show link state of waybar only |
| `symlink-dotfiles --edit waybar` | open waybar config in `$EDITOR` |
| `symlink-dotfiles --push` | commit + push all changes with an auto message |
| `symlink-dotfiles --push 'tweak waybar'` | commit + push with a custom message |
| `symlink-dotfiles --unlink` | remove all symlinks and restore latest backups |
| `symlink-dotfiles --unlink waybar` | unlink waybar only |
| `symlink-dotfiles --restore waybar` | interactively pick a backup to restore for waybar |
| `symlink-dotfiles --dry-run` | preview what would happen without making changes |
| `symlink-dotfiles --clean-backups` | prune old backups, keeping the 3 most recent per config |
| `symlink-dotfiles --help` | show all flags and examples |

## How it works

- **Symlinking** — each folder in `.dotfiles/.config` is symlinked into `~/.config`. Because they're symlinks, any edits you make in `~/.config` are instantly reflected in the repo and tracked by git.
- **Auto-detect** — no hardcoded config list. Any folder you add to `.dotfiles/.config` will be picked up automatically on the next run.
- **Backups** — anything that was in `~/.config` before linking is moved to `.dotfiles/.backup` with a timestamp (e.g. `waybar_2026-03-09_14-32-01`). Multiple backups are kept per config and can be restored interactively with `--restore`.
- **Auto-pull** — every run after the first does a `git pull` before symlinking, keeping your configs up to date. If the repo has uncommitted local changes the pull is skipped and you're prompted to `--push` first.
- **Self-update** — after a successful pull, if the script in the repo differs from the one in `/bin`, it updates itself automatically.
- **Broken symlink repair** — if a symlink points to a missing target (e.g. after a bad pull), it's detected and re-linked automatically.
