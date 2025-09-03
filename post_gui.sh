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
# THEMEFLIP
# ==============================================================================

if confirm_step "Apply Theme"; then
  info "Applying theme using themeflip..."
  if command -v themeflip >/dev/null 2>&1; then
    themeflip
    success "Theme applied."
  else
    error "themeflip command not found. Please ensure it is in your PATH."
  fi
else
  warn "Skipping theme application."
fi

# ==============================================================================
# YAY AND AUR PACKAGES
# ==============================================================================

if confirm_step "Install AUR Helper (yay) and Packages"; then
  info "Installing yay-bin from AUR..."
  if ! command -v yay >/dev/null 2>&1; then
    mkdir -p ~/.local/src
    cd ~/.local/src
    if [ ! -d "yay-bin" ]; then
      sudo pacman -S --needed --noconfirm git base-devel && git clone https://aur.archlinux.org/yay-bin.git
    fi
    cd yay-bin
    makepkg -si --noconfirm
    cd "$HOME"
    success "yay installed."
  else
    info "yay is already installed."
  fi

  info "Installing packages from AUR using yay from aur.txt..."
  if [ -f "aur.txt" ]; then
    yay -S --needed --noconfirm - <aur.txt || error "Failed to install AUR packages."
    success "AUR packages installed."
  else
    error "aur.txt not found."
  fi
else
  warn "Skipping AUR helper and package installation."
fi

# ==============================================================================
# COMPILE FROM SOURCE
# ==============================================================================

if confirm_step "Compile Tools from Source"; then
  info "Compiling and installing local source tools..."

  compile_and_install() {
    local dir=$1
    info "Processing $dir..."
    if [ -d "$dir" ]; then
      cd "$dir" || {
        warn "Could not cd into $dir"
        return
      }
      bear -- make
      sudo make install
      cd "$HOME"
    else
      warn "Directory not found: $dir"
    fi
  }

  compile_and_install "$HOME/.local/src/lf-file-handler"
  compile_and_install "$HOME/.local/src/fetch"

  info "Processing fast-files..."
  if [ -d "$HOME/.local/src/fast-files" ]; then
    cd "$HOME/.local/src/fast-files"
    sudo make install
    cd "$HOME"
  else
    warn "Directory not found: $HOME/.local/src/fast-files"
  fi

  info "Processing pandoc-sidenote..."
  if [ -d "$HOME/.local/src/pandoc-sidenote" ]; then
    warn "Directory already exists: $HOME/.local/src/pandoc-sidenote"
  else
    git clone https://github.com/jez/pandoc-sidenote "$HOME/.local/src/pandoc-sidenote" || {
      warn "Failed to clone pandoc-sidenote"
      return
    }
  fi

  if [ -d "$HOME/.local/src/pandoc-sidenote" ]; then
    cd "$HOME/.local/src/pandoc-sidenote" || {
      warn "Could not cd into pandoc-sidenote"
      return
    }
    stack build || {
      warn "Failed to build pandoc-sidenote"
      return
    }
    stack install || {
      warn "Failed to install pandoc-sidenote"
      return
    }
    cd "$HOME"
  else
    warn "Directory not found: $HOME/.local/src/pandoc-sidenote"
  fi

  success "Finished compiling tools from source."
else
  warn "Skipping compilation of local tools."
fi

# ==============================================================================
# OTHER PACKAGE MANAGERS
# ==============================================================================

if confirm_step "Install npm and pipx Packages"; then
  info "Installing global npm packages from npm.txt..."
  if [ -f "npm.txt" ]; then
    xargs -a npm.txt npm install -g || error "npm install failed."
    success "npm packages installed."
  else
    error "npm.txt not found."
  fi

  info "Installing pipx packages from pipx.txt..."
  if [ -f "pipx.txt" ]; then
    while IFS= read -r package; do
      pipx install "$package" || error "pipx install failed for $package."
    done <pipx.txt
    success "pipx packages installed."
  else
    error "pipx.txt not found."
  fi
else
  warn "Skipping npm and pipx package installation."
fi

# ==============================================================================
# NEOVIM SETUP
# ==============================================================================

if confirm_step "Setup Neovim (Lazy Sync)"; then
  info "Running Lazy sync for Neovim..."
  nvim --headless "+Lazy! sync" +qa || error "Neovim Lazy sync failed."
  success "Neovim setup complete."
else
  warn "Skipping Neovim setup."
fi

# ==============================================================================
# MPV SCRIPTS
# ==============================================================================

install_mpv_scripts() {
  info "Installing mpv scripts..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/tomasklaen/uosc/HEAD/installers/unix.sh)" || error "Failed to install uosc."
  mkdir -p ~/.config/mpv/scripts
  mkdir -p ~/.config/mpv/script-opts
  curl -L https://raw.githubusercontent.com/po5/thumbfast/master/thumbfast.lua -o ~/.config/mpv/scripts/thumbfast.lua || error "Failed to download thumbfast.lua."
  curl -L https://raw.githubusercontent.com/po5/thumbfast/master/thumbfast.conf -o ~/.config/mpv/script-opts/thumbfast.conf || error "Failed to download thumbfast.conf."

  info "Installing ikatube mpv plugin..."
  curl -L https://chino-chan.gitlab.io/programs.html -o ~/.cache/ikatubepage.html || error "Failed to download ikatube page."
  URL=$(grep "ikatube-mpvplugin" ~/.cache/ikatubepage.html | awk -F'"' '{print $2}')
  PLUGIN_URL="https://chino-chan.gitlab.io/$URL"
  curl -L "$PLUGIN_URL" -o ~/.cache/ikatubeplugin.zip || error "Failed to download ikatube plugin."
  unzip -o ~/.cache/ikatubeplugin.zip -d ~/.cache || error "Failed to unzip ikatube plugin."
  cp -r ~/.cache/ikatube-mpvplugin/ikatube ~/.config/mpv/ikatube || error "Failed to copy ikatube config."
  SCRIPT_PATH=$(find ~/.cache/ikatube-mpvplugin -maxdepth 1 -type f -name "*ikatube*.so" | head -n 1)
  cp "$SCRIPT_PATH" ~/.config/mpv/scripts || error "Failed to copy ikatube script."
  rm -rf ~/.cache/ikatubeplugin.zip ~/.cache/ikatubepage.html ~/.cache/ikatube-mpvplugin

  info "Please change ikatube config manually if needed."
  sleep 2
  nvim ~/.config/mpv/ikatube/ikatube.json
  success "mpv scripts installed."
}

if confirm_step "Install mpv scripts"; then
  install_mpv_scripts
else
  warn "Skipping mpv script installation."
fi

# ==============================================================================
# NEWSBOAT URLS
# ==============================================================================

restore_newsboat_urls() {
  info "Restoring newsboat URLs..."
  if [ -f ~/backup/newsboat_urls ]; then
    cp -iv ~/backup/newsboat_urls ~/.config/newsboat/urls
    success "Newsboat URLs restored."
  else
    warn "Newsboat urls backup not found at ~/backup/newsboat_urls"
  fi
}

if confirm_step "Restore newsboat URLs"; then
  restore_newsboat_urls
else
  warn "Skipping newsboat URL restoration."
fi

# ==============================================================================
# CHANGE TTY FONT
# ==============================================================================

change_tty_font() {
  info "Changing TTY font..."
  if [[ $EUID -ne 0 ]]; then
    error "This step must be run as root."
  fi

  local FONT_NAME="iso07u-16"
  local FONT_PATH="/usr/share/kbd/consolefonts/${FONT_NAME}.psfu.gz"
  local VCONSOLE_CONF="/etc/vconsole.conf"
  local BACKUP_CONF="/etc/vconsole.conf.bak.$(date +%s)"

  if [[ ! -f "$FONT_PATH" ]]; then
    error "Font file not found: $FONT_PATH"
  fi

  info "Backing up $VCONSOLE_CONF to $BACKUP_CONF"
  cp "$VCONSOLE_CONF" "$BACKUP_CONF"

  if grep -q "^FONT=" "$VCONSOLE_CONF"; then
    sed -i "s/^FONT=.*/FONT=${FONT_NAME}/" "$VCONSOLE_CONF"
  else
    echo "FONT=${FONT_NAME}" >>"$VCONSOLE_CONF"
  fi
  success "TTY font set to '$FONT_NAME'."
}

if confirm_step "Change TTY font"; then
  sudo bash -c "$(declare -f change_tty_font); change_tty_font"
else
  warn "Skipping TTY font change."
fi

# ==============================================================================
# GRUB
# ==============================================================================

configure_grub() {
  info "Configuring bigger GRUB font..."
  if [[ $EUID -ne 0 ]]; then
    error "This step must be run as root."
  fi

  if confirm_step "Mount Windows EFI for GRUB?"; then
    info "Mounting Windows EFI..."
    mounter || warn "Mounter script failed or was cancelled."
  else
    warn "Skipping Windows EFI mount."
  fi

  local FONT_SIZE="20"
  local FONT_NAME="DejaVuSansMono$FONT_SIZE"
  local USER_HOME
  USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  local TTF_PATH="$USER_HOME/.local/share/fonts/dejavu/DejaVuSansMono.ttf"
  local GRUB_FONT="/boot/grub/fonts/${FONT_NAME}.pf2"
  local GRUB_CFG="/etc/default/grub"

  if [ ! -f "$TTF_PATH" ]; then
    error "Dejavu font not found at $TTF_PATH"
  fi

  info "Generating GRUB font..."
  grub-mkfont -s "$FONT_SIZE" -o "$GRUB_FONT" "$TTF_PATH" || error "Failed to generate GRUB font."

  if ! grep -q "^GRUB_FONT=" "$GRUB_CFG"; then
    info "Setting GRUB_FONT in $GRUB_CFG"
    printf '\nGRUB_FONT=%s\n' "$GRUB_FONT" >>"$GRUB_CFG"
  else
    info "Updating existing GRUB_FONT line"
    sed -i "s|^GRUB_FONT=.*|GRUB_FONT=${GRUB_FONT}|" "$GRUB_CFG"
  fi

  info "Enabling OS Prober..."
  sed -i 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' "$GRUB_CFG"

  info "Updating GRUB configuration..."
  grub-mkconfig -o /boot/grub/grub.cfg || error "grub-mkconfig failed."

  success "GRUB font configured."
    # GRUB Theme Installation
    if confirm_step "Install LainGrubTheme?"; then
      info "Cloning and installing LainGrubTheme..."
      git clone --depth=1 https://github.com/uiriansan/LainGrubTheme /tmp/LainGrubTheme && \
      cd /tmp/LainGrubTheme && \
      sudo ./install.sh && \
      cd -
      success "LainGrubTheme installed."
    else
      warn "Skipping LainGrubTheme installation."
    fi
}

if confirm_step "GRUB Configuration"; then
  sudo bash -c "$(declare -f configure_grub); configure_grub"
else
  warn "Skipping GRUB configuration."
fi

  # ======================================================================
  # SDDM Theme Installation
  # ======================================================================

  if confirm_step "Install SilentSDDM Theme?"; then
    info "Cloning and installing SilentSDDM theme..."
    git clone -b main --depth=1 https://github.com/uiriansan/SilentSDDM /tmp/SilentSDDM && \
    cd /tmp/SilentSDDM && \
    sudo ./install.sh && \
    cd -
    success "SilentSDDM theme installed."
  else
    warn "Skipping SilentSDDM theme installation."
  fi

# ==============================================================================
# CHANGE GETTY ISSUE
# ==============================================================================

update_getty_issue() {
  info "Updating /etc/issue..."
  if [[ $EUID -ne 0 ]]; then
    error "This step must be run as root."
  fi

  cat <<'EOF' >/etc/issue
 [H [2J
            [0;36m.                                                      [0;36m| \s \r
           [0;36m/ \                                                     [0;36m|  [0;37m\m
          [0;36m/   \       [1;37m               #      [1;36m| *                      [0;36m|
         [0;36m/^.   \      [1;37m a##e #%" a#"e 6##%   [1;36m| | |-^-. |   | \ /      [0;36m|  [0;37m\t
        [0;36m/  .-.  \     [1;37m.oOo# #   #    #  #   [1;36m| | |   | |   |  X       [0;36m|  [0;37m\d
       [0;36m/  (   ) _\    [1;37m%OoO# #   %#e" #  #   [1;36m| | |   | ^._.| / \  [0;37mTM   [0;36m|
      [1;36m/ _.~   ~._^\                                                [0;36m|  [0;37m\U
     [1;36m/.^         ^.\  [0;37mTM                                            [0;36m| \l  [0;37mon \n
 [0m
EOF
  success "/etc/issue has been updated."
}

if confirm_step "Update /etc/issue"; then
  sudo bash -c "$(declare -f update_getty_issue); update_getty_issue"
else
  warn "Skipping /etc/issue update."
fi

# ==============================================================================
# SKIP USERNAME
# ==============================================================================

setup_auto_login() {
  info "Setting up auto-login..."
  if [[ $EUID -ne 0 ]]; then
    error "This step must be run as root."
  fi

  if ! command -v fzf >/dev/null 2>&1; then
    error "fzf is not installed. Please install it first."
  fi

  local USERNAME
  USERNAME=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | fzf --prompt="Select user for auto-login: ")

  if [ -z "$USERNAME" ]; then
    warn "No user selected. Skipping auto-login setup."
    return
  fi

  mkdir -p /etc/systemd/system/getty@tty1.service.d/
  cat <<EOF >/etc/systemd/system/getty@tty1.service.d/skip-username.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -- $USERNAME' --noclear --skip-login - \$TERM
EOF

  success "Auto-login configured for user: $USERNAME"
}

if confirm_step "Setup auto-login (skip username prompt)"; then
  sudo bash -c "$(declare -f setup_auto_login); setup_auto_login"
else
  warn "Skipping auto-login setup."
fi

# ==============================================================================
# FIREFOX SETUP
# ==============================================================================

setup_firefox() {
  info "Setting up Firefox..."
  info "Opening Firefox Headless..."
  firefox --headless &
  sleep 5
  local PROFILE_DIR="$HOME/.mozilla/firefox"
  local BACKUP_DIR="$HOME/backup/firefox_places"
  local USER_JS_URL="https://raw.githubusercontent.com/yokoffing/Betterfox/main/user.js"

  info "Killing Firefox Headless..."
  pkill --exact firefox || true
  sleep 2

  restore_firefox_profile() {
    local PROFILE_NAME="$1"
    local PROFILE_PATH="$2"
    local BACKUP_FILE="$BACKUP_DIR/places_${PROFILE_NAME}.sqlite"

    if [ -d "$PROFILE_PATH" ]; then
      info "Restoring profile '$PROFILE_NAME' to '$PROFILE_PATH'"
      cp -v "$BACKUP_FILE" "$PROFILE_PATH/places.sqlite"
      chmod 600 "$PROFILE_PATH/places.sqlite"
      chown "$USER:$USER" "$PROFILE_PATH/places.sqlite"
      success "Restored profile '$PROFILE_NAME'."
    else
      warn "Firefox profile path for '$PROFILE_NAME' not found or is not a directory: $PROFILE_PATH"
    fi
  }

  apply_firefox_userjs() {
    local PROFILE_PATH="$1"
    if [ -d "$PROFILE_PATH" ]; then
      info "Applying user.js to profile: $PROFILE_PATH"
      curl -sSL "$USER_JS_URL" -o "$PROFILE_PATH/user.js"
      chmod 644 "$PROFILE_PATH/user.js"
      cat <<EOF >>"$PROFILE_PATH/user.js"
/****************************************************************************
 * START: MY OVERRIDES                                                      *
****************************************************************************/
user_pref("browser.tabs.closeWindowWithLastTab", false);
user_pref("layout.css.devPixelsPerPx", "0.95");
user_pref("media.videocontrols.picture-in-picture.video-toggle.enabled", false);
user_pref("browser.startup.homepage", "chrome://browser/content/blanktab.html");
user_pref("browser.newtabpage.enabled", false);
user_pref("ui.context_menus.after_mouseup", true);
EOF
      success "Applied user.js to $PROFILE_PATH"
    else
      warn "Profile path not found, skipping user.js for: $PROFILE_PATH"
    fi
  }

  install_firefox_addons() {
    local profile_path="$1"
    shift
    local addonlist="$@"
    local addontmp
    addontmp="$(mktemp -d)"
    trap "rm -fr $addontmp" HUP INT QUIT TERM PWR EXIT

    info "Installing addons for profile: $profile_path"
    mkdir -p "$profile_path/extensions/"

    for addon in $addonlist; do
      info "Processing addon: $addon"
      local addonurl
      addonurl="$(curl --silent "https://addons.mozilla.org/en-US/firefox/addon/${addon}/" | grep -o 'https://addons.mozilla.org/firefox/downloads/file/[^"\n]*')"

      if [ -z "$addonurl" ]; then
        warn "Could not find download URL for $addon"
        continue
      fi

      local file="${addonurl##*/}"
      curl -Ls "$addonurl" -o "$addontmp/$file"

      local id
      id=$(unzip -p "$addontmp/$file" manifest.json 2>/dev/null | jq -r '.id // .browser_specific_settings.gecko.id')

      if [ "$id" = "null" ] || [ -z "$id" ]; then
        if unzip -l "$addontmp/$file" | grep -q "mozilla-recommendation.json"; then
          id=$(unzip -p "$addontmp/$file" mozilla-recommendation.json | jq -r '.addon_id')
        fi
      fi

      if [ "$id" != "null" ] && [ -n "$id" ]; then
        mv "$addontmp/$file" "$profile_path/extensions/$id.xpi"
        success "Installed $addon"
      else
        warn "Could not find addon ID for $addon"
      fi
    done
  }

  firefox --CreateProfile "olddefault" >/dev/null

  local PROFILE_PATH_DEFAULT_RELEASE
  PROFILE_PATH_DEFAULT_RELEASE=$(find "$PROFILE_DIR" -maxdepth 1 -type d -name "*default-release*" | head -n 1)
  local PROFILE_PATH_OLDDEFAULT
  PROFILE_PATH_OLDDEFAULT=$(find "$PROFILE_DIR" -maxdepth 1 -type d -name "*olddefault*" | head -n 1)

  restore_firefox_profile "default-release" "$PROFILE_PATH_DEFAULT_RELEASE"
  restore_firefox_profile "olddefault" "$PROFILE_PATH_OLDDEFAULT"

  apply_firefox_userjs "$PROFILE_PATH_DEFAULT_RELEASE"
  apply_firefox_userjs "$PROFILE_PATH_OLDDEFAULT"

  local default_release_addons="ublock-origin sponsorblock bitwarden-password-manager turbo-download-manager tridactyl-vim youtube-shorts-block sci-hub-addon"
  local olddefault_addons="ublock-origin bitwarden-password-manager turbo-download-manager youtube-shorts-block proton-vpn-firefox-extension 4chanx imagus"

  install_firefox_addons "$PROFILE_PATH_DEFAULT_RELEASE" $default_release_addons
  install_firefox_addons "$PROFILE_PATH_OLDDEFAULT" $olddefault_addons

  info "Launching 'default-release'..."
  firefox -P "default-release" --no-remote \
    "about:settings#search" \
    "about:addons" \
    "https://github.com/yokoffing/filterlists#guidelines" &

  info "Launching 'olddefault'..."
  firefox -P "olddefault" --no-remote \
    "about:settings#search" \
    "about:addons" \
    "https://github.com/yokoffing/filterlists#guidelines" &

  info "Go through each open tab in both profiles and configure accordingly"
  info "Update Ublock Filters"
  info "Log in to password manager"
  info "Set compact mode for both profiles and customize toolbar"
  info "Set Ctrl+H to sort by last visited for both profiles"
  input "Press Enter once done..."
  read -r
  success "Firefox setup complete."
}

if confirm_step "Setup Firefox"; then
  setup_firefox
else
  warn "Skipping Firefox setup."
fi

# ==============================================================================
# FSTAB SETUP
# ==============================================================================

setup_fstab() {
  info "Setting up /etc/fstab..."
  info "Mount windows drives using the dmenu mounter script."
  sleep 2
  mounter || warn "mounter command failed."
  sleep 2
  mounter || warn "mounter command failed."
  sleep 2
  mounter || warn "mounter command failed."

  sudo genfstab / >~/fstab
  if command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard <~/fstab
    info "Generated fstab entries copied to clipboard."
  else
    warn "xclip not found. Please copy the contents of ~/fstab manually."
    cat ~/fstab
  fi

  input "Paste the copied entries into /etc/fstab now. Opening nvim... Press Enter to continue."
  read -r
  sudoedit /etc/fstab
  info "Now check if mounted partitions work as expected."
  success "fstab setup complete."
}

if confirm_step "Setup /etc/fstab"; then
  setup_fstab
else
  warn "Skipping fstab setup."
fi

# ==============================================================================
# MISCELLANEOUS SETUP
# ==============================================================================

setup_misc() {
  info "Performing miscellaneous setup tasks..."

  info "Cloning voidrice repository..."
  if [ ! -d "$HOME/.local/src/voidrice" ]; then
    git clone https://github.com/lukesmithxyz/voidrice.git ~/.local/src/voidrice
  else
    info "voidrice repository already exists."
  fi

  info "Cloning/pulling bookmarks repository..."
  if [ -d "$HOME/.local/src/bookmarks/.git" ]; then
    git -C "$HOME/.local/src/bookmarks" pull --rebase
  else
    git clone https://github.com/fmhy/bookmarks.git "$HOME/.local/src/bookmarks"
  fi

  info "Creating symbolic links for media folders..."
  ln -sfn /mnt/d/Music ~/Music
  ln -sfn /mnt/e/me ~/Me

  info "Setting up cmus..."
  input "Add music folder to cmus and set theme to night, then press Enter to continue..."
  cmus
  read -r

  info "Creating download directories..."
  mkdir -p ~/Downloads/Images/Screenshots
  mkdir -p ~/Downloads/Videos/Recordings

  info "Creating lf marks..."
  local USERNAME
  USERNAME=$(whoami)
  local MARKS_FILE="$HOME/.local/share/lf/marks"
  mkdir -p "$(dirname "$MARKS_FILE")"
  cat <<EOF >"$MARKS_FILE"
c:/mnt/c
d:/mnt/d
e:/mnt/e
r:/home/$USERNAME/Downloads/Videos/Recordings
s:/home/$USERNAME/Downloads/Images/Screenshots
w:/home/$USERNAME/.config/x11/themeconf
EOF

  info "Updating tldr database..."
  tldr --update

  info "Configuring qalc..."
  if command -v qalc >/dev/null 2>&1; then
    setsid -f qalc &
    sleep 2
    echo 'calculate_as_you_type=1' >>~/.config/qalculate/qalc.cfg
  else
    warn "qalc command not found."
  fi
  success "Miscellaneous setup complete."
}

if confirm_step "Perform miscellaneous setup"; then
  setup_misc
else
  warn "Skipping miscellaneous setup."
fi

# ==============================================================================
# FINAL REBOOT
# ==============================================================================

success "Post-GUI setup script finished!"

if confirm_step "Reboot"; then
  info "Rebooting now..."
  sudo reboot
else
  info "Please reboot manually."
fi

info "Script finished!"
success "All tasks completed."
