#!/bin/bash

# Resolve the real user's home even when run with sudo
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

DOTFILES_DIR="$REAL_HOME/.dotfiles/.config"
CONFIG_DIR="$REAL_HOME/.config"
BACKUP_DIR="$REAL_HOME/.dotfiles/.backup"
INSTALL_FLAG="$REAL_HOME/.dotfiles/.installed"
SCRIPT_NAME="symlink-dotfiles"

CONFIGS=(
    "fastfetch"
    "hypr"
    "kitty"
    "supertuxkart"
    "swaync"
    "waybar"
    "wofi"
)

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# ── First-run bootstrap ────────────────────────────────────────────────────────
if [ ! -f "$INSTALL_FLAG" ]; then
    echo -e "${BLUE}SETUP${NC}  First run detected — bootstrapping..."
    echo "──────────────────────────────────────────────────────"

    # Create dotfiles folders
    mkdir -p "$DOTFILES_DIR"
    mkdir -p "$BACKUP_DIR"
    chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.dotfiles"
    echo -e "${GREEN}MKDIR${NC}  $DOTFILES_DIR"
    echo -e "${GREEN}MKDIR${NC}  $BACKUP_DIR"

    # Move script to /bin
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

    # Mark as installed
    touch "$INSTALL_FLAG"
    chown "$REAL_USER:$REAL_USER" "$INSTALL_FLAG"
    echo "──────────────────────────────────────────────────────"
    echo -e "${GREEN}DONE${NC}   Bootstrap complete. Run '${SCRIPT_NAME}' from anywhere."
    echo ""
fi
# ──────────────────────────────────────────────────────────────────────────────

echo "Symlinking dotfiles from $DOTFILES_DIR → $CONFIG_DIR"
echo "──────────────────────────────────────────────────────"

for config in "${CONFIGS[@]}"; do
    src="$DOTFILES_DIR/$config"
    dest="$CONFIG_DIR/$config"

    # Check source exists
    if [ ! -e "$src" ]; then
        echo -e "${RED}SKIP${NC}   $config  (source not found in .dotfiles)"
        continue
    fi

    # Already a correct symlink
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        echo -e "${GREEN}OK${NC}     $config  (already linked)"
        continue
    fi

    # Back up existing dir/file
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        mv "$dest" "$BACKUP_DIR/$config"
        echo -e "${YELLOW}BACKUP${NC} $config  → .dotfiles/.backup/$config"
    fi

    ln -s "$src" "$dest"
    echo -e "${GREEN}LINKED${NC} $config"
done

echo "──────────────────────────────────────────────────────"
echo "Done."
