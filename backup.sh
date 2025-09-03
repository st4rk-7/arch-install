#!/usr/bin/env sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { printf "${BLUE}INFO:${NC} %s\n" "$1"; }
success() { printf "${GREEN}SUCCESS:${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}WARNING:${NC} %s\n" "$1"; }
input() { printf "${BLUE}INPUT REQUIRED:${NC} %s" "$1"; }
error() {
  printf "${RED}ERROR:${NC} %s\n" "$1"
  exit 1
}

# --------------------------------------------
# Dependency Check
# --------------------------------------------

REQUIRED_TOOLS="git lazygit nvim zip rsync pcshare find tar"

missing_tools=""

for tool in $REQUIRED_TOOLS; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing_tools="$missing_tools $tool"
  fi
done

if [ -n "$missing_tools" ]; then
  warn "Missing required tools:$missing_tools"
  warn "Please install them before running this script."
  exit 1
fi

# --------------------------------------------
# Commit and Push Dotfiles via lazygit
# --------------------------------------------

cd "$HOME/dotfiles" || error "Could not cd into '~/dotfiles'."

is_repo_clean() {
  [ -z "$(git ls-files --others --exclude-standard)" ] &&
    [ -z "$(git diff --name-only)" ] &&
    [ -z "$(git diff --cached --name-only)" ] &&
    [ -z "$(git rev-list @{u}..HEAD 2>/dev/null)" ]
}

while true; do
  if is_repo_clean; then
    break
  else
    warn "dotfiles repo still has pending changes."
    input "Open lazygit? [Y/n]: "
    read choice
    case "$choice" in
    [nN]*) break ;;
    *) lazygit ;;
    esac
  fi
done

if is_repo_clean; then
  DOTFILES_BACKUP="$HOME/backup/dotfiles"
  # info "Backing up clean dotfiles repo to '$DOTFILES_BACKUP'..."
  mkdir -p "$DOTFILES_BACKUP"
  rsync -a --exclude='.git' ./ "$DOTFILES_BACKUP/"
  if [ $? -eq 0 ]; then
    success "dotfiles copied to '$DOTFILES_BACKUP'."
  else
    warn "Failed to copy dotfiles."
  fi
fi

cd "$HOME" || error "Could not return to home directory."

# --------------------------------------------
# Backup Fonts
# --------------------------------------------

FONT_DIR="$HOME/.local/share/fonts"
FONT_BACKUP="$HOME/backup"

if [ ! -d "$FONT_DIR" ]; then
  warn "Fonts directory '$FONT_DIR' not found; skipping font backup."
else
  cd "$FONT_DIR" || error "Failed to cd into '$FONT_DIR'."
  find . -type f -o -type d | zip -@ "font_backup.zip" >/dev/null 2>&1
  if [ -f "font_backup.zip" ]; then
    mkdir -p "$FONT_BACKUP"
    mv "font_backup.zip" "$FONT_BACKUP" || error "Failed to move font_backup.zip."
    success "Fonts backed up to '$FONT_BACKUP'."
  else
    error "font_backup.zip was not created."
  fi
  cd "$HOME" || error "Failed to return to home directory."
fi

# --------------------------------------------
# Backup Firefox Bookmarks & History
# --------------------------------------------

PROFILE_DIR="$HOME/.mozilla/firefox"
BACKUP_DIR="$HOME/backup/firefox_places"
mkdir -p "$BACKUP_DIR" || error "Failed to create '$BACKUP_DIR'."

for PROFILE_NAME in "default-release" "olddefault"; do
  PROFILE_PATH=$(find "$PROFILE_DIR" -maxdepth 1 -type d -name "*$PROFILE_NAME*" | head -n 1)
  if [ -d "$PROFILE_PATH" ]; then
    SRC="$PROFILE_PATH/places.sqlite"
    DEST="$BACKUP_DIR/places_${PROFILE_NAME}.sqlite"
    if [ -f "$SRC" ]; then
      cp "$SRC" "$DEST" || warn "Failed to copy '$SRC'."
      if [ -f "$DEST" ]; then
        success "Backed up '$SRC'."
      else
        warn "Backup '$DEST' not found after copy."
      fi
    else
      warn "File '$SRC' not found for profile '$PROFILE_NAME'."
    fi
  else
    warn "Profile directory matching '*$PROFILE_NAME*' not found."
  fi
done

# --------------------------------------------
# Backup Newsboat URLs
# --------------------------------------------

NEWSBOAT_SRC="$HOME/.config/newsboat/urls"
NEWSBOAT_DEST="$HOME/backup/newsboat-urls"

if [ -f "$NEWSBOAT_SRC" ]; then
  cp "$NEWSBOAT_SRC" "$NEWSBOAT_DEST" || warn "Failed to copy Newsboat URLs."
  if [ -f "$NEWSBOAT_DEST" ]; then
    success "Newsboat URLs backed up to '$NEWSBOAT_DEST'."
  else
    warn "Backup file '$NEWSBOAT_DEST' not found."
  fi
else
  warn "Newsboat URL file '$NEWSBOAT_SRC' does not exist; skipping."
fi

# --------------------------------------------
# Backup zsh exports
# --------------------------------------------

EXPORTS_SRC="$HOME/.config/shell/exports"
EXPORTS_DEST="$HOME/backup/shell-exports"

if [ -f "$EXPORTS_SRC" ]; then
  cp "$EXPORTS_SRC" "$EXPORTS_DEST" || warn "Failed to copy exports file"
  if [ -f "$EXPORTS_DEST" ]; then
    success "Zsh exorts backed up to '$EXPORTS_DEST'."
  else
    warn "Backup file '$EXPORTS_DEST' not found."
  fi
else
  warn "Zsh exports file '$EXPORTS_SRC' does not exist; skipping."
fi

# --------------------------------------------
# Backup SSH Keys
# --------------------------------------------

SSH_DIR="$HOME/.ssh"
SSH_ARCHIVE="$HOME/backup/ssh_backup.tar.gz"

if [ -d "$SSH_DIR" ]; then
  tar -czvf "$SSH_ARCHIVE" -C "$HOME" .ssh >/dev/null 2>&1
  if [ -f "$SSH_ARCHIVE" ]; then
    success "SSH keys archived to '$SSH_ARCHIVE'."
  else
    error "Failed to create SSH backup archive."
  fi
else
  warn "SSH directory '$SSH_DIR' not found; skipping SSH backup."
fi

# --------------------------------------------
# Backup /etc/fstab
# --------------------------------------------

mkdir -p "$HOME/backup" || error "Failed to create '$HOME/backup'."
cp /etc/fstab "$HOME/backup/fstab.bak" || error "Failed to copy /etc/fstab."

if [ -f "$HOME/backup/fstab.bak" ]; then
  success "fstab backed up as '$HOME/backup/fstab.bak'."
else
  error "Backup file '$HOME/backup/fstab.bak' was not found."
fi

# --------------------------------------------
# Backup
# --------------------------------------------

if [ ! -d "$HOME/backup" ]; then
  error "Backup folder does not exist at $HOME/backup"
fi

get_usb_folders() {
  local folders=()
  for dir in /mnt/usb*; do
    if [ -d "$dir" ] && mountpoint -q "$dir"; then
      folders+=("$dir")
    fi
  done
  printf "%s\n" "${folders[@]}"
}

if [ -z "$(get_usb_folders)" ]; then
  input "No USB device found. Do you want to mount one using the mounter script? [Y/n]: "
  read -r choice
  case "$choice" in
  [nN]*)
    info "Compressing the backup directory..."
    info "Name the zip 'backup'"
    compressor "$HOME/backup"
    success "Backup directory compressed."
    ;;
  *)
    mounter
    ;;
  esac
fi

USB_FOLDERS=($(get_usb_folders))

if [ ${#USB_FOLDERS[@]} -gt 0 ]; then
  if [ ${#USB_FOLDERS[@]} -eq 1 ]; then
    chosen_folder="${USB_FOLDERS[0]}"
  else
    info "Mounted USB folders found:"
    for i in "${!USB_FOLDERS[@]}"; do
      printf "%s) %s\n" "$((i + 1))" "${USB_FOLDERS[i]}"
    done

    while true; do
      input "Enter the number of the folder to move the backup to: "
      read -r choice
      if [ "$choice" -ge 1 ] && [ "$choice" -le ${#USB_FOLDERS[@]} ]; then
        chosen_folder="${USB_FOLDERS[$((choice - 1))]}"
        break
      else
        warn "Invalid choice. Please try again."
      fi
    done
  fi

  if [ -n "$chosen_folder" ]; then
    info "Moving backup folder to $chosen_folder"
    rsync -a --delete "$HOME/backup/" "$chosen_folder/backup/"
    success "Backup completed successfully."
  else
    error "Invalid choice. Exiting."
  fi
fi


# --------------------------------------------
# Done
# --------------------------------------------
success "Backup script completed."
