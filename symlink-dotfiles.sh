#!/bin/bash

# Resolve the real user's home even when run with sudo
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

DOTFILES_DIR="$REAL_HOME/.dotfiles/.config"    # auto-detected configs → ~/.config
EXTERNAL_DIR="$REAL_HOME/.dotfiles/.external"  # manifest-tracked configs → arbitrary paths
MANIFEST="$REAL_HOME/.dotfiles/manifest"       # format: <name> <target_path>
CONFIG_DIR="$REAL_HOME/.config"
BACKUP_DIR="$REAL_HOME/.dotfiles/.backup"
INSTALL_FLAG="$REAL_HOME/.dotfiles/.installed"
SCRIPT_NAME="symlink-dotfiles"
REPO_SCRIPT="$REAL_HOME/.dotfiles/$SCRIPT_NAME.sh"
REPO_DIR="$REAL_HOME/.dotfiles"
KEEP_BACKUPS=3

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

# ── Manifest helpers ──────────────────────────────────────────────────────────
# Read manifest into parallel arrays: MANIFEST_NAMES, MANIFEST_TARGETS
load_manifest() {
    MANIFEST_NAMES=()
    MANIFEST_TARGETS=()
    [ -f "$MANIFEST" ] || return
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip blank lines and comments
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        name="$(echo "$line" | awk '{print $1}')"
        target="$(echo "$line" | awk '{print $2}')"
        MANIFEST_NAMES+=("$name")
        MANIFEST_TARGETS+=("$target")
    done < "$MANIFEST"
}

# Look up the target path for a given external name
manifest_target() {
    local name="$1"
    load_manifest
    for i in "${!MANIFEST_NAMES[@]}"; do
        if [ "${MANIFEST_NAMES[$i]}" = "$name" ]; then
            echo "${MANIFEST_TARGETS[$i]}"
            return
        fi
    done
}

# Add an entry to the manifest
manifest_add() {
    local name="$1" target="$2"
    mkdir -p "$(dirname "$MANIFEST")"
    echo "$name $target" >> "$MANIFEST"
    chown "$REAL_USER:$REAL_USER" "$MANIFEST"
}

# Remove an entry from the manifest
manifest_remove() {
    local name="$1"
    [ -f "$MANIFEST" ] || return
    local tmp
    tmp="$(mktemp)"
    grep -v "^$name " "$MANIFEST" > "$tmp"
    mv "$tmp" "$MANIFEST"
    chown "$REAL_USER:$REAL_USER" "$MANIFEST"
}
# ──────────────────────────────────────────────────────────────────────────────

# ── Combined config source ────────────────────────────────────────────────────
# Returns lines of the form: "name source_path dest_path"
# .config entries: source = DOTFILES_DIR/name, dest = CONFIG_DIR/name
# .external entries: source = EXTERNAL_DIR/name, dest = from manifest
get_all_entries() {
    local filter="$1"

    # Auto-detected .config entries
    while IFS= read -r name; do
        [ -n "$filter" ] && [ "$name" != "$filter" ] && continue
        echo "$name $DOTFILES_DIR/$name $CONFIG_DIR/$name"
    done < <(find "$DOTFILES_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort)

    # Manifest .external entries
    load_manifest
    for i in "${!MANIFEST_NAMES[@]}"; do
        name="${MANIFEST_NAMES[$i]}"
        target="${MANIFEST_TARGETS[$i]}"
        [ -n "$filter" ] && [ "$name" != "$filter" ] && continue
        echo "$name $EXTERNAL_DIR/$name $target"
    done
}
# ──────────────────────────────────────────────────────────────────────────────

# ── Symlink one entry ─────────────────────────────────────────────────────────
link_entry() {
    local name="$1" src="$2" dest="$3" dry_run="$4"
    local timestamp="$5"

    # Detect and fix broken symlinks
    if [ -L "$dest" ] && [ ! -e "$dest" ]; then
        if $dry_run; then
            echo -e "${YELLOW}WOULD${NC}  $name  re-link (broken symlink)"
        else
            echo -e "${YELLOW}BROKEN${NC} $name  (broken symlink — re-linking)"
            rm "$dest"
            mkdir -p "$(dirname "$dest")"
            ln -s "$src" "$dest"
            echo -e "${GREEN}LINKED${NC} $name"
        fi
        return
    fi

    # Already correctly linked
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        $dry_run || echo -e "${GREEN}OK${NC}     $name  (already linked)"
        return
    fi

    # Back up and link
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        if $dry_run; then
            echo -e "${YELLOW}WOULD${NC}  $name  backup → .backup/${name}_${timestamp} then link"
        else
            mkdir -p "$BACKUP_DIR"
            mv "$dest" "$BACKUP_DIR/${name}_${timestamp}"
            echo -e "${YELLOW}BACKUP${NC} $name  → .backup/${name}_${timestamp}"
            mkdir -p "$(dirname "$dest")"
            ln -s "$src" "$dest"
            echo -e "${GREEN}LINKED${NC} $name"
        fi
        return
    fi

    # Nothing there — just link
    if $dry_run; then
        echo -e "${YELLOW}WOULD${NC}  $name  link → $dest"
    else
        mkdir -p "$(dirname "$dest")"
        ln -s "$src" "$dest"
        echo -e "${GREEN}LINKED${NC} $name"
    fi
}
# ──────────────────────────────────────────────────────────────────────────────

# ── Help ──────────────────────────────────────────────────────────────────────
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo -e "Usage: ${CYAN}$SCRIPT_NAME${NC} [flag] [config]"
    echo ""
    echo "When run with no arguments, pulls the latest repo changes and re-links all configs."
    echo ""
    echo -e "  ${GREEN}[config]${NC}                   Target a single config by name"
    echo -e "                             Works with --unlink, --restore, --status, --edit, --dry-run"
    echo ""
    echo -e "  ${GREEN}--add <path>${NC}               Move a folder into .external, register it in the"
    echo -e "                             manifest, and symlink it. The folder's current location"
    echo -e "                             is used as the target path."
    echo -e "  ${GREEN}--remove <name>${NC}            Unlink an external entry and remove it from the manifest"
    echo -e "  ${GREEN}--status${NC}                   Show the link state of all (or one) config(s)"
    echo -e "  ${GREEN}--unlink [config]${NC}          Remove symlinks and restore the latest backup"
    echo -e "  ${GREEN}--restore <config>${NC}         Pick a backup to restore interactively"
    echo -e "  ${GREEN}--edit <config>${NC}            Open a config directory in \$EDITOR"
    echo -e "  ${GREEN}--push [message]${NC}           Commit and push all changes in the dotfiles repo"
    echo -e "  ${GREEN}--dry-run [config]${NC}         Show what would happen without making changes"
    echo -e "  ${GREEN}--clean-backups${NC}            Keep only the $KEEP_BACKUPS most recent backups per config"
    echo -e "  ${GREEN}--help${NC}                     Show this help message"
    echo ""
    echo -e "Examples:"
    echo -e "  $SCRIPT_NAME                                    # pull + re-link everything"
    echo -e "  $SCRIPT_NAME waybar                            # pull + re-link waybar only"
    echo -e "  $SCRIPT_NAME --add /usr/share/sddm/themes/cat  # add external config"
    echo -e "  $SCRIPT_NAME --remove sddm-cat                 # remove external config"
    echo -e "  $SCRIPT_NAME --status                          # check all configs"
    echo -e "  $SCRIPT_NAME --status waybar                   # check waybar only"
    echo -e "  $SCRIPT_NAME --unlink waybar                   # unlink waybar only"
    echo -e "  $SCRIPT_NAME --restore waybar                  # pick a backup to restore"
    echo -e "  $SCRIPT_NAME --edit waybar                     # open waybar config in \$EDITOR"
    echo -e "  $SCRIPT_NAME --push 'tweak waybar'             # commit + push with message"
    echo -e "  $SCRIPT_NAME --dry-run                         # preview all changes"
    echo -e "  $SCRIPT_NAME --clean-backups                   # prune old backups"
    exit 0
fi
# ──────────────────────────────────────────────────────────────────────────────

# ── Add mode ──────────────────────────────────────────────────────────────────
if [ "$1" = "--add" ]; then
    src_path="$(realpath "${2:-}")"
    if [ -z "$src_path" ] || [ ! -e "$src_path" ]; then
        echo -e "${RED}ERROR${NC}  Usage: $SCRIPT_NAME --add <path>"
        echo -e "         Path must exist on the filesystem"
        exit 1
    fi

    name="$(basename "$src_path")"
    dest_in_repo="$EXTERNAL_DIR/$name"

    # Check for name collision
    if [ -d "$dest_in_repo" ]; then
        echo -e "${RED}ERROR${NC}  '$name' already exists in .external — choose a different name"
        exit 1
    fi
    if manifest_target "$name" | grep -q .; then
        echo -e "${RED}ERROR${NC}  '$name' already exists in manifest"
        exit 1
    fi

    mkdir -p "$EXTERNAL_DIR"
    chown "$REAL_USER:$REAL_USER" "$EXTERNAL_DIR"

    # Move folder into .external
    mv "$src_path" "$dest_in_repo"
    chown -R "$REAL_USER:$REAL_USER" "$dest_in_repo"
    echo -e "${GREEN}MOVED${NC}  $src_path → .dotfiles/.external/$name"

    # Register in manifest
    manifest_add "$name" "$src_path"
    echo -e "${GREEN}MANIFEST${NC} Added '$name' → $src_path"

    # Create the symlink
    mkdir -p "$(dirname "$src_path")"
    ln -s "$dest_in_repo" "$src_path"
    echo -e "${GREEN}LINKED${NC} $name → $src_path"

    echo "──────────────────────────────────────────────────────"
    echo "Done. Run '${SCRIPT_NAME} --push' to save to the repo."
    exit 0
fi
# ──────────────────────────────────────────────────────────────────────────────

# ── Remove mode ───────────────────────────────────────────────────────────────
if [ "$1" = "--remove" ]; then
    name="$2"
    if [ -z "$name" ]; then
        echo -e "${RED}ERROR${NC}  Usage: $SCRIPT_NAME --remove <name>"
        exit 1
    fi

    target="$(manifest_target "$name")"
    if [ -z "$target" ]; then
        echo -e "${RED}ERROR${NC}  '$name' not found in manifest"
        exit 1
    fi

    src="$EXTERNAL_DIR/$name"

    # Remove symlink
    if [ -L "$target" ] && [ "$(readlink "$target")" = "$src" ]; then
        rm "$target"
        echo -e "${YELLOW}UNLINKED${NC} $name  ($target)"
    else
        echo -e "${YELLOW}SKIP${NC}   $name symlink not found at $target"
    fi

    # Remove from manifest
    manifest_remove "$name"
    echo -e "${YELLOW}MANIFEST${NC} Removed '$name'"

    # Offer to restore the files to their original location
    read -rp "Restore files back to $target? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        mkdir -p "$(dirname "$target")"
        mv "$src" "$target"
        echo -e "${GREEN}RESTORED${NC} $name → $target"
    else
        echo -e "${YELLOW}NOTE${NC}   Files remain at .dotfiles/.external/$name"
    fi

    echo "──────────────────────────────────────────────────────"
    echo "Done."
    exit 0
fi
# ──────────────────────────────────────────────────────────────────────────────

# ── Status mode ───────────────────────────────────────────────────────────────
if [ "$1" = "--status" ]; then
    TARGET="$2"
    echo -e "${CYAN}STATUS${NC} Checking dotfiles state..."
    echo "──────────────────────────────────────────────────────"

    while IFS=' ' read -r name src dest; do
        target_empty=false
        [ -d "$dest" ] && [ -z "$(ls -A "$dest" 2>/dev/null)" ] && target_empty=true

        # Label external entries
        label="$name"
        [ -d "$EXTERNAL_DIR/$name" ] && label="$name ${CYAN}(external)${NC}"

        if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ] && [ -e "$dest" ]; then
            if $target_empty; then
                echo -e "${YELLOW}LINKED${NC}   $label  (linked but target is empty)"
            else
                echo -e "${GREEN}LINKED${NC}   $label"
            fi
        elif [ -L "$dest" ] && [ ! -e "$dest" ]; then
            echo -e "${RED}BROKEN${NC}   $label  (symlink points to missing target)"
        elif [ -e "$dest" ]; then
            echo -e "${YELLOW}UNMANAGED${NC} $label  (exists but not a managed symlink)"
        else
            echo -e "${RED}MISSING${NC}  $label  (not present at $dest)"
        fi
    done < <(get_all_entries "$TARGET")

    echo "──────────────────────────────────────────────────────"
    exit 0
fi
# ──────────────────────────────────────────────────────────────────────────────

# ── Edit mode ─────────────────────────────────────────────────────────────────
if [ "$1" = "--edit" ]; then
    name="$2"
    if [ -z "$name" ]; then
        echo -e "${RED}ERROR${NC}  Usage: $SCRIPT_NAME --edit <config>"
        exit 1
    fi

    # Check .config first, then .external
    if [ -d "$DOTFILES_DIR/$name" ]; then
        target="$DOTFILES_DIR/$name"
    elif [ -d "$EXTERNAL_DIR/$name" ]; then
        target="$EXTERNAL_DIR/$name"
    else
        echo -e "${RED}ERROR${NC}  '$name' not found in .config or .external"
        exit 1
    fi

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

    echo -e "${CYAN}EDIT${NC}   Opening $name in $EDIT_CMD..."
    sudo -u "$REAL_USER" "$EDIT_CMD" "$target"
    exit 0
fi
# ──────────────────────────────────────────────────────────────────────────────

# ── Push mode ─────────────────────────────────────────────────────────────────
if [ "$1" = "--push" ]; then
    commit_msg="${2:-dotfiles update $(date '+%Y-%m-%d %H:%M')}"
    echo -e "${BLUE}PUSH${NC}   Pushing dotfiles to remote..."
    echo "──────────────────────────────────────────────────────"

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
    name="$2"
    if [ -z "$name" ]; then
        echo -e "${RED}ERROR${NC}  Usage: $SCRIPT_NAME --restore <config>"
        exit 1
    fi

    mapfile -t BACKUPS < <(find "$BACKUP_DIR" -maxdepth 1 -name "${name}_*" -type d 2>/dev/null | sort -r)
    [ -d "$BACKUP_DIR/$name" ] && BACKUPS+=("$BACKUP_DIR/$name")

    if [ ${#BACKUPS[@]} -eq 0 ]; then
        echo -e "${YELLOW}WARN${NC}   No backups found for '$name'"
        exit 0
    fi

    echo -e "${CYAN}RESTORE${NC} Available backups for '$name':"
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

    # Determine the correct destination
    ext_target="$(manifest_target "$name")"
    if [ -n "$ext_target" ]; then
        dest="$ext_target"
    else
        dest="$CONFIG_DIR/$name"
    fi

    [ -L "$dest" ] || [ -e "$dest" ] && rm -rf "$dest"
    mv "$selected" "$dest"
    echo -e "${GREEN}RESTORED${NC} $name  ← $(basename "$selected")"
    echo "──────────────────────────────────────────────────────"
    echo "Done."
    exit 0
fi
# ──────────────────────────────────────────────────────────────────────────────

# ── Unlink mode ───────────────────────────────────────────────────────────────
if [ "$1" = "--unlink" ]; then
    TARGET="$2"
    echo -e "${BLUE}UNLINK${NC} Removing symlinks and restoring backups..."
    echo "──────────────────────────────────────────────────────"

    while IFS=' ' read -r name src dest; do
        latest_backup="$(find "$BACKUP_DIR" -maxdepth 1 -name "${name}_*" -type d 2>/dev/null | sort | tail -1)"
        plain_backup="$BACKUP_DIR/$name"

        if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
            rm "$dest"
            if [ -n "$latest_backup" ]; then
                mv "$latest_backup" "$dest"
                echo -e "${GREEN}RESTORED${NC} $name  ← $(basename "$latest_backup")"
            elif [ -e "$plain_backup" ]; then
                mv "$plain_backup" "$dest"
                echo -e "${GREEN}RESTORED${NC} $name  ← .backup/$name"
            else
                echo -e "${YELLOW}REMOVED${NC}  $name  (no backup to restore)"
            fi
        else
            echo -e "${YELLOW}SKIP${NC}   $name  (not a managed symlink)"
        fi
    done < <(get_all_entries "$TARGET")

    echo "──────────────────────────────────────────────────────"
    echo "Done."
    exit 0
fi
# ──────────────────────────────────────────────────────────────────────────────

# ── Clean backups mode ────────────────────────────────────────────────────────
if [ "$1" = "--clean-backups" ]; then
    echo -e "${BLUE}CLEAN${NC}  Pruning old backups (keeping $KEEP_BACKUPS per config)..."
    echo "──────────────────────────────────────────────────────"

    while IFS=' ' read -r name src dest; do
        mapfile -t ALL_BACKUPS < <(find "$BACKUP_DIR" -maxdepth 1 -name "${name}_*" -type d 2>/dev/null | sort)
        total=${#ALL_BACKUPS[@]}

        if [ "$total" -le "$KEEP_BACKUPS" ]; then
            echo -e "${GREEN}OK${NC}     $name  ($total backup(s), nothing to prune)"
            continue
        fi

        to_delete=$(( total - KEEP_BACKUPS ))
        for (( i=0; i<to_delete; i++ )); do
            rm -rf "${ALL_BACKUPS[$i]}"
            echo -e "${YELLOW}PRUNED${NC} $name  → $(basename "${ALL_BACKUPS[$i]}")"
        done
    done < <(get_all_entries "")

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

        mkdir -p "$BACKUP_DIR" "$EXTERNAL_DIR"
        chown "$REAL_USER:$REAL_USER" "$BACKUP_DIR" "$EXTERNAL_DIR"
        echo -e "${GREEN}MKDIR${NC}  $BACKUP_DIR"
        echo -e "${GREEN}MKDIR${NC}  $EXTERNAL_DIR"

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

        if ! sudo -u "$REAL_USER" git -C "$REPO_DIR" diff --quiet || \
           ! sudo -u "$REAL_USER" git -C "$REPO_DIR" diff --cached --quiet; then
            echo -e "${YELLOW}WARN${NC}   Repo has uncommitted changes — skipping pull to avoid conflicts"
            echo -e "         Run '${CYAN}$SCRIPT_NAME --push${NC}' to commit them first, or resolve manually."
        else
            if sudo -u "$REAL_USER" git -C "$REPO_DIR" pull --ff-only; then
                echo -e "${GREEN}DONE${NC}   Repo is up to date"

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

# ── Link all configs ──────────────────────────────────────────────────────────
mapfile -t ENTRIES < <(get_all_entries "$TARGET")

if [ ${#ENTRIES[@]} -eq 0 ]; then
    echo -e "${RED}ERROR${NC}  No configs found"
    exit 1
fi

$DRY_RUN || echo "Symlinking dotfiles..."
$DRY_RUN || echo "──────────────────────────────────────────────────────"

TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"

for entry in "${ENTRIES[@]}"; do
    name="$(echo "$entry" | awk '{print $1}')"
    src="$(echo "$entry"  | awk '{print $2}')"
    dest="$(echo "$entry" | awk '{print $3}')"
    link_entry "$name" "$src" "$dest" "$DRY_RUN" "$TIMESTAMP"
done

echo "──────────────────────────────────────────────────────"
echo "Done."
