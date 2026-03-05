# dotfiles

My personal Hyprland dotfiles for Fedora Linux. Configs are managed with symlinks so any changes made to the files are automatically tracked by git.

## what's included

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

## fresh install

Make sure `git` is installed, then:

```bash
# clone the repo
git clone https://github.com/09superfish/dotfiles.git ~/.dotfiles

# run it (sudo needed only the first time to install the script to /bin)
sudo ~/.dotfiles/symlink-dotfiles.sh
```

The script will:
- Create `~/.dotfiles/.config` and `~/.dotfiles/.backup` if they don't exist
- Install itself to `/bin/symlink-dotfiles` so you can run it from anywhere
- Symlink each config into `~/.config`, backing up anything that was already there to `~/.dotfiles/.backup`

After the first run, just call `symlink-dotfiles` from anywhere to re-link everything.
