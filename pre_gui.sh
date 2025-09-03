#!/usr/bin/env bash

set -euo pipefail

# ==============================================================================
# HELPER FUNCTIONS AND SETUP
# ==============================================================================

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
info() { printf "\n${BLUE}INFO:${NC} %s\n" "$1"; }
success() { printf "${GREEN}SUCCESS:${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}WARNING:${NC} %s\n" "$1"; }
input() { printf "${BLUE}INPUT REQUIRED:${NC} %s" "$1"; }
error() {
  printf "${RED}ERROR:${NC} %s\n" "$1"
  exit 1
}

# Confirmation function
confirm_step() {
  while true; do
    input "Proceed with '$1'? [y/N]: "
    read -r response
    case "$response" in
    [yY]) return 0 ;;
    [nN] | "") return 1 ;;
    *) warn "Invalid input. Please enter 'y' or 'n'." ;;
    esac
  done
}

# ==============================================================================
# PACMAN CONFIGURATION
# ==============================================================================

if confirm_step "Pacman Configuration"; then
  info "Tweaking pacman.conf for a better experience..."
  PACMAN_CONF="/etc/pacman.conf"
  BACKUP_CONF="/etc/pacman.conf.bak"

  if [ ! -f "$BACKUP_CONF" ]; then
    sudo cp "$PACMAN_CONF" "$BACKUP_CONF"
    success "Backup of pacman.conf created at $BACKUP_CONF"
  else
    info "Backup already exists at $BACKUP_CONF"
  fi

  TMP_CONF=$(mktemp)
  while IFS= read -r line; do
    trimmed="$(printf "%s" "$line" | sed 's/^[[:space:]]*//')"
    case "$trimmed" in
    "Color" | "#Color")
      echo "Color" >>"$TMP_CONF"
      if ! grep -q '^ILoveCandy' "$PACMAN_CONF"; then
        echo "ILoveCandy" >>"$TMP_CONF"
      fi
      ;;
    "VerbosePkgLists" | "#VerbosePkgLists") echo "VerbosePkgLists" >>"$TMP_CONF" ;;
    "ParallelDownloads"* | "#ParallelDownloads"*) echo "ParallelDownloads = 5" >>"$TMP_CONF" ;;
    *) echo "$line" >>"$TMP_CONF" ;;
    esac
  done <"$PACMAN_CONF"

  sudo mv "$TMP_CONF" "$PACMAN_CONF"
  sudo chmod 644 "$PACMAN_CONF"
  success "Successfully updated $PACMAN_CONF."
  info "Showing differences from backup:"
  diff --color=always -u "$BACKUP_CONF" "$PACMAN_CONF" || true
else
  warn "Skipping Pacman Configuration."
fi

# ==============================================================================
# UPDATE MIRRORS
# ==============================================================================

if confirm_step "Update Mirrors"; then
  info "Updating mirrorlist with reflector..."
  MIRRORLIST="/etc/pacman.d/mirrorlist"
  BACKUP_MIRRORLIST="/etc/pacman.d/mirrorlist.bak.$(date +%F-%H%M%S)"

  if ! command -v reflector >/dev/null 2>&1; then
    info "Installing reflector..."
    sudo pacman -S --noconfirm reflector || error "Failed to install reflector."
  fi

  info "Backing up current mirrorlist to $BACKUP_MIRRORLIST"
  sudo cp "$MIRRORLIST" "$BACKUP_MIRRORLIST" || error "Mirrorlist backup failed"

  info "Ranking and updating mirrors..."
  if sudo reflector -f 30 -l 30 --number 10 --download-timeout 30 --verbose --save "$MIRRORLIST"; then
    success "Mirrorlist successfully updated."
  else
    warn "Reflector failed. Restoring backup..."
    sudo cp "$BACKUP_MIRRORLIST" "$MIRRORLIST"
    error "Restored the previous mirrorlist. Please check your connection."
  fi
else
  warn "Skipping Mirror Update."
fi

# ==============================================================================
# INSTALL PACMAN PACKAGES
# ==============================================================================

if confirm_step "Install Pacman Packages"; then
  info "Installing all essential pacman packages from pacman.txt..."
  if [ -f "pacman.txt" ]; then
    sudo pacman -S --needed --noconfirm - <pacman.txt || error "Pacman package installation failed."
    success "All pacman packages installed."
  else
    error "pacman.txt not found."
  fi
else
  warn "Skipping Pacman Package Installation."
fi

# ==============================================================================
# UNZIP BACKUP
# ==============================================================================

if confirm_step "Restore Backup"; then
  info "Preparing to restore backup..."
  BACKUP_DEST="$HOME"

  input "Get backup from (1:usb/2:network)? [1/2]: "
  read -r source

  if [[ "$source" == "1" ]]; then
    info "Please plug in your USB device now."
    read -p "Press ENTER once the USB is connected..."
    lsblk
    input "Enter the device path (e.g., /dev/sdX1): "
    read -r device_path
    MOUNT_POINT="/mnt/usb1"
    sudo mkdir -p "$MOUNT_POINT"
    info "Mounting $device_path to $MOUNT_POINT..."
    sudo mount "$device_path" "$MOUNT_POINT" || error "Failed to mount USB device"
    src_path="$MOUNT_POINT/backup"
    if [[ -d "$src_path" ]]; then
      info "Copying backup folder from USB..."
      cp -r "$src_path" "$HOME/backup" || error "Failed to copy backup from USB"
      success "Backup copied to $HOME/backup"
    else
      error "Backup folder not found on USB at $src_path"
    fi
    info "Unmounting USB..."
    sudo umount "$MOUNT_POINT"
    success "USB unmounted."
  elif [[ "$source" == "2" ]]; then
    input "Enter the URL to the encrypted backup.zip: "
    read -r zip_url
    temp_dir=$(mktemp -d)
    zip_path="$temp_dir/backup.zip"
    info "Downloading backup from network..."
    curl -L "$zip_url" -o "$zip_path" || error "Failed to download backup.zip"
    input "Enter the password to decrypt backup.zip: "
    read -rs zip_password
    echo
    info "Extracting encrypted zip file..."
    7z x -p"$zip_password" "$zip_path" -o"$BACKUP_DEST" || error "Failed to extract backup.zip"
    success "Backup extracted to $BACKUP_DEST"
    rm -rf "$temp_dir"
  else
    error "Invalid option. Choose '1' or '2'."
  fi
else
  warn "Skipping Backup Restoration."
fi

# ==============================================================================
# GIT CONFIGURATION
# ==============================================================================

if confirm_step "Git Configuration"; then
  info "Configuring Git..."
  mkdir -p "$HOME/.config/git"
  touch "$HOME/.config/git/config"
  git config --global user.name "st4rk"
  git config --global user.email "st4rk.7@proton.me"
  git config --global init.defaultBranch main
  git config --global pull.rebase false
  success "Git configured."
else
  warn "Skipping Git Configuration."
fi

# ==============================================================================
# RESTORE SSH KEYS
# ==============================================================================

if confirm_step "Restore SSH Keys"; then
  info "Restoring SSH keys..."
  mkdir -p "$HOME/.ssh"
  if [ -f "$HOME/backup/ssh_backup.tar.gz" ]; then
    tar -xzvf "$HOME/backup/ssh_backup.tar.gz" -C "$HOME"
    chmod 700 "$HOME/.ssh"
    chmod 600 "$HOME/.ssh/id_"* 2>/dev/null
    chmod 644 "$HOME/.ssh/"*.pub 2>/dev/null
    chown -R "$USER:$USER" "$HOME/.ssh"
    success "SSH keys restored from backup."
  else
    warn "SSH backup not found. A new key will be generated."
  fi

  if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    info "Generating new ED25519 SSH key..."
    ssh-keygen -t ed25519 -C "st4rk.7@proton.me" -N ""
    info "Please add this public key to your GitHub account:"
    cat "$HOME/.ssh/id_ed25519.pub"
    input "Press ENTER when you have added the key to GitHub..."
    read -r
  fi

  info "Testing SSH connection to GitHub..."
  ssh -T git@github.com || warn "Could not connect to GitHub. Please verify your SSH key setup."
else
  warn "Skipping SSH Key Restoration."
fi

# ==============================================================================
# CLONE AND STOW DOTFILES
# ==============================================================================

if confirm_step "Clone and Stow Dotfiles"; then
  info "Cloning and stowing dotfiles..."
  cd "$HOME"
  if [ ! -d "$HOME/dotfiles" ]; then
    git clone git@github.com:st4rk-7/dotfiles.git --depth=1 --recursive
  else
    warn "$HOME/dotfiles already exists. Skipping clone."
  fi
  cd dotfiles
  git submodule foreach 'git checkout main || git checkout master' >/dev/null
  mkdir -p ~/.config/{dunst,gtk-2.0,gtk-3.0,kitty,mpv,newsboat,shell,x11,zsh/completions}
  mkdir -p ~/.local/bin
  cd ~/dotfiles/scripts/.local/bin
  chmod +x stower unstower
  ./stower
  cd "$HOME"
  success "Dotfiles stowed."
else
  warn "Skipping Dotfiles."
fi

# ==============================================================================
# ZSH CONFIGURATION
# ==============================================================================

if confirm_step "Zsh Configuration"; then
  info "Configuring Zsh..."
  mkdir -p "$HOME/.cache/zsh"
  touch "$HOME/.cache/zsh/history"

  ZSH_PATH=$(which zsh)
  if [ -z "$ZSH_PATH" ]; then
    error "zsh not found, but it should have been installed. Aborting."
  fi

  if [ "$SHELL" != "$ZSH_PATH" ]; then
    if chsh -s "$ZSH_PATH"; then
      success "Changed login shell to: $ZSH_PATH"
    else
      error "Failed to change login shell. Try running with sudo or check /etc/shells."
    fi
  else
    info "zsh is already the default shell."
  fi

  if [ -x "$HOME/.local/bin/zsh_updater" ]; then
    info "Running zsh_updater..."
    "$HOME"/.local/bin/zsh_updater
  else
    warn "zsh_updater not found or not executable."
  fi
  cd "$HOME"
else
  warn "Skipping Zsh Configuration."
fi

# ==============================================================================
# ZSH EXPORTS
# ==============================================================================

if confirm_step "Restore zsh exports"; then
  info "Restoring zsh exports..."
  if [ -f ~/backup/shell-exports ]; then
    cp -iv ~/backup/shell-exports ~/.config/shell/exports
    success "Zsh exports restored."
  else
    warn "Zsh exports backup not found at ~/backup/shell-exports"
  fi
else
  warn "Skipping zsh exports restoration."
fi

# ==============================================================================
# COMPILE SUCKLESS UTILS
# ==============================================================================

if confirm_step "Compile Suckless Utilities"; then
  info "Compiling and installing suckless utilities (dmenu, dwm, st, etc.)..."
  for program in dmenu dwm dwmblocks st slock; do
    dir="$HOME/.config/suckless/$program"
    if [ -d "$dir" ]; then
      cd "$dir" || continue
      info "Adding remotes..."
      case "$program" in
      dmenu) git remote add upstream https://github.com/bakkeby/dmenu-flexipatch.git 2>/dev/null ;;
      dwm) git remote add upstream https://github.com/bakkeby/dwm-flexipatch.git 2>/dev/null ;;
      st) git remote add upstream https://github.com/bakkeby/st-flexipatch.git 2>/dev/null ;;
      slock) git remote add upstream https://github.com/bakkeby/slock-flexipatch.git 2>/dev/null ;;
      dwmblocks) git remote add upstream https://github.com/UtkarshVerma/dwmblocks-async.git 2>/dev/null ;;
      esac
      git fetch upstream
      git config merge.ours.driver true
      info "Installing $program..."
      sudo make install
    else
      warn "Directory not found for $program: $dir"
    fi
  done
  success "Suckless utilities installed."
else
  warn "Skipping Suckless Utilities."
fi

# ==============================================================================
# FONTS
# ==============================================================================

setup_fonts() {
  info "Setting up fonts..."
  mkdir -p "$HOME/.local/share/fonts"
  if [ -f ~/backup/font_backup.zip ]; then
    unzip -o ~/backup/font_backup.zip -d ~/.local/share/fonts || warn "Failed to restore personal font backup."
  else
    warn "Personal font backup not found at ~/backup/font_backup.zip"
  fi

  local texlive_fonts=(cantarell plex fontawesome garamond-libre garamond-math gfsbodoni gfsdidot
    inconsolata inter kpfonts-otf libertine libertinus-fonts montserrat newcomputermodern
    stix2-otf tex-gyre tex-gyre-math opensans librebaskerville dejavu lato
  )

  info "Linking fonts from Texlive..."
  for font in "${texlive_fonts[@]}"; do
    font_path=$(find /usr/share/texmf-dist/fonts/opentype /usr/share/texmf-dist/fonts/truetype -type d -name "$font" -print -quit)
    if [[ -n "$font_path" ]]; then
      ln -sfn "$font_path" ~/.local/share/fonts/"$font"
    else
      warn "Font not found: $font"
    fi
  done

  info "Updating font cache..."
  fc-cache -v
  success "Fonts setup complete."
}

if confirm_step "Setup fonts"; then
  setup_fonts
else
  warn "Skipping font setup."
fi

# ==============================================================================
# CONFIGURE TOUCHPAD
# ==============================================================================

if confirm_step "Configure Touchpad"; then
  info "Configuring touchpad..."
  CONFIG_DIR="/etc/X11/xorg.conf.d"
  if [ ! -d "$CONFIG_DIR" ]; then
    sudo mkdir -p "$CONFIG_DIR"
  fi

  info "Existing configurations in ${CONFIG_DIR}:"
  ls -1 "${CONFIG_DIR}" || warn "Could not list files in ${CONFIG_DIR}."

  input "Enter a two-digit prefix for the new touchpad config (e.g., 30): "
  read -r PREFIX

  if ! printf "%s" "$PREFIX" | grep -Eq '^[0-9]{2}$'; then
    error "Invalid prefix. Must be exactly two digits."
  fi

  CONF_FILE="${CONFIG_DIR}/${PREFIX}-touchpad.conf"
  info "Creating touchpad configuration at $CONF_FILE..."

  sudo sh -c "cat <<EOF > '$CONF_FILE'
Section \"InputClass\"
  Identifier \"touchpad\"
  Driver \"libinput\"
  MatchIsTouchpad \"on\"
  Option \"Tapping\" \"on\"
  Option \"AccelProfile\" \"adaptive\"
  Option \"TappingButtonMap\" \"lrm\"
EndSection
EOF
"
  success "Touchpad configuration written to: $CONF_FILE"
else
  warn "Skipping Touchpad Configuration."
fi

# ==============================================================================
# pacman hook to keep package lists updated
# ==============================================================================

if confirm_step "Packman pkglist hook"; then
  info "Creating pacman hook to track package lists."
  USER_NAME=$(whoami)
  HOOK_DIR="/etc/pacman.d/hooks"
  HOOK_FILE="$HOOK_DIR/track_pkglist.hook"
  SAVE_DIR="/home/$USER_NAME/.local/src/arch-install"

  sudo mkdir -p "$HOOK_DIR"
  mkdir -p "$SAVE_DIR"

  sudo tee "$HOOK_FILE" >/dev/null <<EOF
[Trigger]
Operation = Install
Operation = Remove
Type = Package
Target = *

[Action]
Description = Updating package lists (pacman.txt and aur.txt)...
When = PostTransaction
Exec = /bin/sh -c '/usr/bin/pacman -Qqen > $SAVE_DIR/pacman.txt && /usr/bin/pacman -Qqem | grep -vE "(-debug$|^yay-bin$)" > $SAVE_DIR/aur.txt'
EOF

  success "Hook created at $HOOK_FILE"
  success "Package lists will be saved under: $SAVE_DIR"
else
  warn "Skipping Packman pkglist hook."
fi

# ==============================================================================
# REBOOT
# ==============================================================================

if confirm_step "Reboot System"; then
  success "Initial setup complete!"
  info "Rebooting now."
  sudo reboot
else
  warn "Skipping reboot. The system requires a reboot for all changes to take effect."
fi
