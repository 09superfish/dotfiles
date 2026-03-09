#!/bin/bash

# Resolve the real user's home even when run with sudo
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

DOTFILES_DIR="$REAL_HOME/.dotfiles/.config"
CONFIG_DIR="$REAL_HOME/.config"
BACKUP_DIR="$REAL_HOME/.dotfiles/.backup"
INSTALL_FLAG="$REAL_HOME/.dotfiles/.installed"
SCRIPT_NAME="symlink-dotfiles"
REPO_SCRIPT="$REAL_HOME/.dotfiles/$SCRIPT_NAME.sh"
REPO_DIR="$REAL_HOME/.dotfiles"
KEEP_BACKUPS=3   # number of backups to keep per config during --clean-backups

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Dependency check ───────────────────────────────────────────────────────────
if ! command -v git &>/dev/null; then
    echo -e "${RED}ERROR${NC}  git is not installed — please install it and try again"
    exit 1
fi
# ──────────────────────────────────────────────────────────────────────────────

# ── Help ──────────────────────────────────────────────────────────────────────
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo -e "Usage: ${CYAN}$SCRIPT_NAME${NC} [flag] [config]"
    echo ""
    echo "When run with no arguments, pulls the latest repo changes and re-links all configs."
    echo ""
    echo -e "  ${GREEN}[config]${NC}              Target a single config (e.g. waybar, kitty)"
    echo -e "                        Works with --unlink, --restore, --status, --edit, and --dry-run"
    echo ""
    echo -e "  ${GREEN}--status${NC}              Show the link state of all (or one) config(s)"
    echo -e "  ${GREEN}--unlink${NC}              Remove symlinks and restore the latest backup"
    echo -e "  ${GREEN}--restore <config>${NC}    Pick a backup to restore for a config interactively"
    echo -e "  ${GREEN}--edit <config>${NC}       Open a config directory in \$EDITOR"
    echo -e "  ${GREEN}--push [message]${NC}      Commit and push all changes in the dotfiles repo"
    echo -e "  ${GREEN}--dry-run${NC}             Show what would happen without making any changes"
    echo -e "  ${GREEN}--clean-backups${NC}       Keep only the $KEEP_BACKUPS most recent backups per config"
    echo -e "  ${GREEN}--help${NC}                Show this help message"
    echo ""
    echo -e "Examples:"
    echo -e "  $SCRIPT_NAME                          # pull + re-link everything"
    echo -e "  $SCRIPT_NAME waybar                   # pull + re-link waybar only"
    echo -e "  $SCRIPT_NAME --status                 # check all configs"
    echo -e "  $SCRIPT_NAME --status waybar          # check waybar only"
    echo -e "  $SCRIPT_NAME --unlink waybar          # unlink waybar only"
    echo -e "  $SCRIPT_NAME --restore waybar         # pick a backup to restore for waybar"
    echo -e "  $SCRIPT_NAME --edit waybar            # open waybar config in \$EDITOR"
    echo -e "  $SCRIPT_NAME --push                   # commit + push with auto message"
    echo -e "  $SCRIPT_NAME --push 'tweak waybar'    # commit + push with custom message"
    echo -e "  $SCRIPT_NAME --dry-run                # preview all changes"
    echo -e "  $SCRIPT_NAME --clean-backups          # prune old backups"
    exit 0
fi
# ──────────────────────────────────────────────────────────────────────────────

# ── Helper: resolve config list (all or single) ───────────────────────────────
get_configs() {
    local filter="$1"
    if [ -n "$filter" ]; then
        if [ -d "$DOTFILES_DIR/$filter" ]; then
            echo "$filter"
        else
            echo -e "${RED}ERROR${NC}  '$filter' not found in $DOTFILES_DIR" >&2
            exit 1
        fi
    else
        find "$DOTFILES_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
    fi
}
# ──────────────────────────────────────────────────────────────────────────────

# ── Status mode ───────────────────────────────────────────────────────────────
if [ "$1" = "--status" ]; then
    TARGET="$2"
    mapfile -t CONFIGS < <(get_configs "$TARGET")
    echo -e "${CYAN}STATUS${NC} Checking dotfiles state..."
    echo "──────────────────────────────────────────────────────"

    for config in "${CONFIGS[@]}"; do
        src="$DOTFILES_DIR/$config"
        dest="$CONFIG_DIR/$config"
        target_empty=false
        [ -d "$dest" ] && [ -z "$(ls -A "$dest" 2>/dev/null)" ] && target_empty=true

        if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ] && [ -e "$dest" ]; then
            if $target_empty; then
                echo -e "${YELLOW}LINKED${NC}   $config  (linked but target directory is empty)"
            else
                echo -e "${GREEN}LINKED${NC}   $config"
            fi
        elif [ -L "$dest" ] && [ ! -e "$dest" ]; then
            echo -e "${RED}BROKEN${NC}   $config  (symlink points to missing target)"
        elif [ -e "$dest" ]; then
            echo -e "${YELLOW}UNMANAGED${NC} $config  (exists but is not a managed symlink)"
        else
            echo -e "${RED}MISSING${NC}  $config  (not present in ~/.config)"
        fi
    done

    echo "──────────────────────────────────────────────────────"
    exit 0
fi
# ──────────────────────────────────────────────────────────────────────────────

# ── Edit mode ─────────────────────────────────────────────────────────────────
if [ "$1" = "--edit" ]; then
    config="$2"
    if [ -z "$config" ]; then
        echo -e "${RED}ERROR${NC}  Usage: $SCRIPT_NAME --edit <config>"
        exit 1
    fi
    target="$DOTFILES_DIR/$config"
    if [ ! -d "$target" ]; then
        echo -e "${RED}ERROR${NC}  '$config' not found in $DOTFILES_DIR"
        exit 1
    fi

    # Resolve editor: prefer $EDITOR, fall back to common options
    EDIT_CMD="${EDITOR:-}"
    if [ -z "$EDIT_CMD" ]; then
        for candidate in nvim vim nano; do
            if command -v "$candidate" &>/dev/null; then
                EDIT_CMD="$candidate"
                break
            fi
        done
    fi

    if [ -z "$EDIT_CMD" ]; then
        echo -e "${RED}ERROR${NC}  No editor found — set \$EDITOR or install vim/nvim/nano"
        exit 1
    fi

    echo -e "${CYAN}EDIT${NC}   Opening $config in $EDIT_CMD..."
    sudo -u "$REAL_USER" "$EDIT_CMD" "$target"
    exit 0
fi
# ──────────────────────────────────────────────────────────────────────────────

# ── Push mode ─────────────────────────────────────────────────────────────────
if [ "$1" = "--push" ]; then
    commit_msg="${2:-dotfiles update $(date '+%Y-%m-%d %H:%M')}"

    echo -e "${BLUE}PUSH${NC}   Pushing dotfiles to remote..."
    echo "──────────────────────────────────────────────────────"

    # Check there's anything to commit
    if sudo -u "$REAL_USER" git -C "$REPO_DIR" diff --quiet && \
       sudo -u "$REAL_USER" git -C "$REPO_DIR" diff --cached --quiet && \
       [ -z "$(sudo -u "$REAL_USER" git -C "$REPO_DIR" ls-files --others --exclude-standard)" ]; then
        echo -e "${YELLOW}NOTHING${NC} No changes to commit"
        exit 0
    fi

    sudo -u "$REAL_USER" git -C "$REPO_DIR" add -A && \
    sudo -u "$REAL_USER" git -C "$REPO_DIR" commit -m "$commit_msg" && \
    sudo -u "$REAL_USER" git -C "$REPO_DIR" push \
        && echo -e "${GREEN}DONE${NC}   Pushed: \"$commit_msg\"" \
        || { echo -e "${RED}ERROR${NC}  Push failed — check your remote and credentials"; exit 1; }

    echo "──────────────────────────────────────────────────────"
    echo "Done."
    exit 0
fi
# ──────────────────────────────────────────────────────────────────────────────

# ── Restore mode ──────────────────────────────────────────────────────────────
if [ "$1" = "--restore" ]; then
    config="$2"
    if [ -z "$config" ]; then
        echo -e "${RED}ERROR${NC}  Usage: $SCRIPT_NAME --restore <config>"
        exit 1
    fi
    if [ ! -d "$DOTFILES_DIR/$config" ]; then
        echo -e "${RED}ERROR${NC}  '$config' not found in $DOTFILES_DIR"
        exit 1
    fi

    mapfile -t BACKUPS < <(find "$BACKUP_DIR" -maxdepth 1 -name "${config}_*" -type d 2>/dev/null | sort -r)
    [ -d "$BACKUP_DIR/$config" ] && BACKUPS+=("$BACKUP_DIR/$config")

    if [ ${#BACKUPS[@]} -eq 0 ]; then
        echo -e "${YELLOW}WARN${NC}   No backups found for '$config'"
        exit 0
    fi

    echo -e "${CYAN}RESTORE${NC} Available backups for '$config':"
    echo "──────────────────────────────────────────────────────"
    for i in "${!BACKUPS[@]}"; do
        echo -e "  ${GREEN}$((i+1))${NC}  $(basename "${BACKUPS[$i]}")"
    done
    echo ""
    read -rp "Choose backup to restore [1-${#BACKUPS[@]}]: " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#BACKUPS[@]}" ]; then
        echo -e "${RED}ERROR${NC}  Invalid choice"
        exit 1
    fi

    selected="${BACKUPS[$((choice-1))]}"
    dest="$CONFIG_DIR/$config"

    if [ -L "$dest" ] || [ -e "$dest" ]; then
        rm -rf "$dest"
    fi

    mv "$selected" "$dest"
    echo -e "${GREEN}RESTORED${NC} $config  ← $(basename "$selected")"
    echo "──────────────────────────────────────────────────────"
    echo "Done."
    exit 0
fi
# ──────────────────────────────────────────────────────────────────────────────

# ── Unlink mode ───────────────────────────────────────────────────────────────
if [ "$1" = "--unlink" ]; then
    TARGET="$2"
    mapfile -t CONFIGS < <(get_configs "$TARGET")
    echo -e "${BLUE}UNLINK${NC} Removing symlinks and restoring backups..."
    echo "──────────────────────────────────────────────────────"

    for config in "${CONFIGS[@]}"; do
        src="$DOTFILES_DIR/$config"
        dest="$CONFIG_DIR/$config"
        latest_backup="$(find "$BACKUP_DIR" -maxdepth 1 -name "${config}_*" -type d 2>/dev/null | sort | tail -1)"
        plain_backup="$BACKUP_DIR/$config"

        if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
            rm "$dest"
            if [ -n "$latest_backup" ]; then
                mv "$latest_backup" "$dest"
                echo -e "${GREEN}RESTORED${NC} $config  ← $(basename "$latest_backup")"
            elif [ -e "$plain_backup" ]; then
                mv "$plain_backup" "$dest"
                echo -e "${GREEN}RESTORED${NC} $config  ← .backup/$config"
            else
                echo -e "${YELLOW}REMOVED${NC}  $config  (no backup to restore)"
            fi
        else
            echo -e "${YELLOW}SKIP${NC}   $config  (not a managed symlink)"
        fi
    done

    echo "──────────────────────────────────────────────────────"
    echo "Done."
    exit 0
fi
# ──────────────────────────────────────────────────────────────────────────────

# ── Clean backups mode ────────────────────────────────────────────────────────
if [ "$1" = "--clean-backups" ]; then
    echo -e "${BLUE}CLEAN${NC}  Pruning old backups (keeping $KEEP_BACKUPS per config)..."
    echo "──────────────────────────────────────────────────────"

    mapfile -t CONFIGS < <(get_configs "")

    for config in "${CONFIGS[@]}"; do
        mapfile -t ALL_BACKUPS < <(find "$BACKUP_DIR" -maxdepth 1 -name "${config}_*" -type d 2>/dev/null | sort)
        total=${#ALL_BACKUPS[@]}

        if [ "$total" -le "$KEEP_BACKUPS" ]; then
            echo -e "${GREEN}OK${NC}     $config  ($total backup(s), nothing to prune)"
            continue
        fi

        to_delete=$(( total - KEEP_BACKUPS ))
        for (( i=0; i<to_delete; i++ )); do
            rm -rf "${ALL_BACKUPS[$i]}"
            echo -e "${YELLOW}PRUNED${NC} $config  → $(basename "${ALL_BACKUPS[$i]}")"
        done
    done

    echo "──────────────────────────────────────────────────────"
    echo "Done."
    exit 0
fi
# ──────────────────────────────────────────────────────────────────────────────

# ── Dry run / target arg parsing ──────────────────────────────────────────────
DRY_RUN=false
TARGET=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --*) ;;
        *) TARGET="$arg" ;;
    esac
done

if $DRY_RUN; then
    echo -e "${YELLOW}DRY RUN${NC} No changes will be made."
    echo "──────────────────────────────────────────────────────"
fi
# ──────────────────────────────────────────────────────────────────────────────

# ── First-run bootstrap ────────────────────────────────────────────────────────
if [ ! -f "$INSTALL_FLAG" ]; then
    if $DRY_RUN; then
        echo -e "${YELLOW}WOULD${NC}  Clone repo into ~/.dotfiles"
        echo -e "${YELLOW}WOULD${NC}  Install script to /bin/$SCRIPT_NAME"
    else
        echo -e "${BLUE}SETUP${NC}  First run detected — bootstrapping..."
        echo "──────────────────────────────────────────────────────"

        if [ -d "$REPO_DIR/.git" ]; then
            echo -e "${YELLOW}SKIP${NC}   Repo already cloned at ~/.dotfiles"
        else
            echo -e "${BLUE}CLONE${NC}  Cloning dotfiles repo into ~/.dotfiles..."
            if sudo -u "$REAL_USER" git clone https://github.com/09superfish/dotfiles.git "$REPO_DIR"; then
                echo -e "${GREEN}DONE${NC}   Repo cloned successfully"
            else
                echo -e "${RED}ERROR${NC}  git clone failed — check your internet connection"
                exit 1
            fi
        fi

        mkdir -p "$BACKUP_DIR"
        chown "$REAL_USER:$REAL_USER" "$BACKUP_DIR"
        echo -e "${GREEN}MKDIR${NC}  $BACKUP_DIR"

        SCRIPT_PATH="$(realpath "$0")"
        if [ "$SCRIPT_PATH" != "/bin/$SCRIPT_NAME" ]; then
            if cp "$SCRIPT_PATH" "/bin/$SCRIPT_NAME" && chmod +x "/bin/$SCRIPT_NAME"; then
                echo -e "${GREEN}MOVED${NC}  Script installed to /bin/$SCRIPT_NAME"
                rm -f "$SCRIPT_PATH"
            else
                echo -e "${RED}ERROR${NC}  Could not install to /bin — try running with sudo"
                exit 1
            fi
        fi

        touch "$INSTALL_FLAG"
        chown "$REAL_USER:$REAL_USER" "$INSTALL_FLAG"
        echo "──────────────────────────────────────────────────────"
        echo -e "${GREEN}DONE${NC}   Bootstrap complete. Run '${SCRIPT_NAME}' from anywhere."
        echo ""
    fi

else
    # ── Pull latest changes + dirty check + self-update ───────────────────────
    if $DRY_RUN; then
        echo -e "${YELLOW}WOULD${NC}  Check for uncommitted changes"
        echo -e "${YELLOW}WOULD${NC}  git pull in ~/.dotfiles"
        echo -e "${YELLOW}WOULD${NC}  Self-update /bin/$SCRIPT_NAME from repo"
    else
        echo -e "${BLUE}PULL${NC}   Checking for updates..."
        echo "──────────────────────────────────────────────────────"

        # Warn if repo has uncommitted changes that could conflict
        if ! sudo -u "$REAL_USER" git -C "$REPO_DIR" diff --quiet || \
           ! sudo -u "$REAL_USER" git -C "$REPO_DIR" diff --cached --quiet; then
            echo -e "${YELLOW}WARN${NC}   Repo has uncommitted changes — skipping pull to avoid conflicts"
            echo -e "         Run '${CYAN}$SCRIPT_NAME --push${NC}' to commit them first, or resolve manually."
        else
            if sudo -u "$REAL_USER" git -C "$REPO_DIR" pull --ff-only; then
                echo -e "${GREEN}DONE${NC}   Repo is up to date"

                # Self-update: overwrite /bin script if repo version differs
                if [ -f "$REPO_SCRIPT" ] && ! diff -q "$REPO_SCRIPT" "/bin/$SCRIPT_NAME" &>/dev/null; then
                    if cp "$REPO_SCRIPT" "/bin/$SCRIPT_NAME" && chmod +x "/bin/$SCRIPT_NAME"; then
                        echo -e "${GREEN}UPDATE${NC} Script updated from repo"
                    else
                        echo -e "${YELLOW}WARN${NC}   Could not self-update script — try running with sudo"
                    fi
                fi
            else
                echo -e "${YELLOW}WARN${NC}   git pull failed — continuing with local files"
            fi
        fi
        echo ""
    fi
fi
# ──────────────────────────────────────────────────────────────────────────────

# ── Auto-detect configs ───────────────────────────────────────────────────────
mapfile -t CONFIGS < <(get_configs "$TARGET")

if [ ${#CONFIGS[@]} -eq 0 ]; then
    echo -e "${RED}ERROR${NC}  No configs found in $DOTFILES_DIR"
    exit 1
fi
# ──────────────────────────────────────────────────────────────────────────────

$DRY_RUN || echo "Symlinking dotfiles from $DOTFILES_DIR → $CONFIG_DIR"
$DRY_RUN || echo "──────────────────────────────────────────────────────"

TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"

for config in "${CONFIGS[@]}"; do
    src="$DOTFILES_DIR/$config"
    dest="$CONFIG_DIR/$config"

    # Detect and fix broken symlinks
    if [ -L "$dest" ] && [ ! -e "$dest" ]; then
        if $DRY_RUN; then
            echo -e "${YELLOW}WOULD${NC}  $config  re-link (broken symlink)"
        else
            echo -e "${YELLOW}BROKEN${NC} $config  (broken symlink — re-linking)"
            rm "$dest"
            ln -s "$src" "$dest"
            echo -e "${GREEN}LINKED${NC} $config"
        fi
        continue
    fi

    # Already a correct symlink
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        $DRY_RUN || echo -e "${GREEN}OK${NC}     $config  (already linked)"
        continue
    fi

    # Back up existing dir/file with timestamp, then link
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        if $DRY_RUN; then
            echo -e "${YELLOW}WOULD${NC}  $config  backup → .backup/${config}_${TIMESTAMP} then link"
        else
            mv "$dest" "$BACKUP_DIR/${config}_${TIMESTAMP}"
            echo -e "${YELLOW}BACKUP${NC} $config  → .dotfiles/.backup/${config}_${TIMESTAMP}"
            ln -s "$src" "$dest"
            echo -e "${GREEN}LINKED${NC} $config"
        fi
        continue
    fi

    # Nothing there — just link
    if $DRY_RUN; then
        echo -e "${YELLOW}WOULD${NC}  $config  link → $dest"
    else
        ln -s "$src" "$dest"
        echo -e "${GREEN}LINKED${NC} $config"
    fi
done

echo "──────────────────────────────────────────────────────"
echo "Done."
