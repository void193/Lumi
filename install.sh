#!/usr/bin/env bash
# Lumi installer for Arch Linux.
#
#   git clone https://github.com/void193/Lumi.git && cd Lumi && ./install.sh
#
# Options:
#   -y, --yes          answer every question with its default (non-interactive)
#   --no-autostart     don't start Lumi automatically after logging in on tty1
#   --no-fish          keep your current login shell
#   --tor              also set up Tor mode and the firewall (asked otherwise)
#   -h, --help         show this help
#
# Everything is logged to ~/lumi-install.log. Existing configs are backed up to
# ~/.config/lumi-backup-<date>/ before anything is replaced.

set -Eeuo pipefail

# Don't rely on the login environment (su, scripts and containers may not set these)
USER=${USER:-$(id -un)}
HOME=${HOME:-$(getent passwd "$USER" | cut -d: -f6)}
export USER HOME

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTS="$REPO_DIR/dots"
SHELL_REPO="https://github.com/void193/LumiShell.git"
SHELL_SRC="${XDG_DATA_HOME:-$HOME/.local/share}/lumi/LumiShell"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
BACKUP="$CONFIG/lumi-backup-$(date +%Y%m%d-%H%M%S)"
LOG="$HOME/lumi-install.log"

ASSUME_YES=0
AUTOSTART=ask
SET_FISH=ask
TOR=ask

# Official repository packages
REPO_PKGS=(
    # Base tooling
    base-devel git curl unzip pacman-contrib xdg-user-dirs xdg-utils

    # Hyprland and desktop plumbing
    hyprland hyprpicker hypridle hyprsunset xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    polkit polkit-gnome gnome-keyring dconf

    # USB drives and phones in the file manager: mounting, auto-mount, thumbnails,
    # and tools for FAT/exFAT/NTFS drives
    gvfs gvfs-mtp gvfs-gphoto2 udisks2 thunar-volman tumbler ffmpegthumbnailer
    dosfstools exfatprogs ntfs-3g

    # Network, bluetooth, power
    networkmanager bluez bluez-utils power-profiles-daemon

    # Audio
    pipewire pipewire-pulse pipewire-alsa wireplumber libpulse

    # Apps used by the keybinds
    foot fish starship eza zoxide direnv thunar firefox btop fuzzel

    # Clipboard, screenshots, notifications
    wl-clipboard cliphist wtype jq grim slurp swappy libnotify trash-cli pciutils

    # Look and feel
    ttf-jetbrains-mono-nerd ttf-cascadia-code-nerd ttf-material-symbols-variable
    noto-fonts noto-fonts-emoji papirus-icon-theme adw-gtk-theme

    # What Lumi's shell and CLI need
    qt6-base qt6-declarative qt6-imageformats qt6-multimedia qt6-multimedia-ffmpeg qt6-shadertools
    ddcutil brightnessctl lm_sensors aubio libqalculate libpipewire
    python python-pillow dart-sass ffmpeg cmake ninja
    python-build python-installer python-hatch python-hatch-vcs

    # Privacy features
    nftables
)

# AUR packages (built with yay or paru)
AUR_PKGS=(
    quickshell-git qt6-m3shapes-git libcava python-materialyoucolor ttf-rubik-vf
    qtengine darkly-bin pwvucontrol bibata-cursor-theme-bin vscodium-bin
)

# ---------------------------------------------------------------------------
# Helpers

if [[ -t 1 ]]; then
    BOLD=$'\e[1m' DIM=$'\e[2m' RED=$'\e[31m' GREEN=$'\e[32m' YELLOW=$'\e[33m' BLUE=$'\e[34m' RESET=$'\e[0m'
else
    BOLD="" DIM="" RED="" GREEN="" YELLOW="" BLUE="" RESET=""
fi

step() { printf '\n%s▍ %s%s\n' "$BLUE$BOLD" "$*" "$RESET"; }
info() { printf '  %s\n' "$*"; }
ok() { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$*"; }
die() {
    printf '\n  %s✗ %s%s\n' "$RED$BOLD" "$*" "$RESET" >&2
    printf '  %sFull log: %s%s\n' "$DIM" "$LOG" "$RESET" >&2
    exit 1
}

# ask "Question?" default(y|n) -> returns 0 for yes
ask() {
    local question=$1 default=$2 reply hint
    [[ $default == y ]] && hint="Y/n" || hint="y/N"
    if ((ASSUME_YES)); then
        [[ $default == y ]]
        return
    fi
    read -r -p "  $question [$hint] " reply </dev/tty || reply=""
    reply=${reply:-$default}
    [[ ${reply,,} == y* ]]
}

on_error() {
    local code=$? line=$1
    printf '\n  %s✗ Something failed (line %s, exit %s).%s\n' "$RED$BOLD" "$line" "$code" "$RESET" >&2
    printf '  %sSee the last lines of %s, and the Troubleshooting section of the README.%s\n' "$DIM" "$LOG" "$RESET" >&2
}
trap 'on_error $LINENO' ERR

usage() {
    sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------------------------------------------------------------------
# Arguments

while (($#)); do
    case $1 in
        -y | --yes) ASSUME_YES=1 ;;
        --no-autostart) AUTOSTART=no ;;
        --no-fish) SET_FISH=no ;;
        --tor) TOR=yes ;;
        -h | --help) usage ;;
        *) die "Unknown option: $1 (see ./install.sh --help)" ;;
    esac
    shift
done

# Log everything from here on, while still showing it
exec > >(tee -a "$LOG") 2>&1

cat <<'EOF'

    ▍ L U M I
    ▍ a quiet, private desktop for Arch Linux

EOF

# ---------------------------------------------------------------------------
step "Checking the system"

[[ $EUID -ne 0 ]] || die "Run this as your normal user, not root (it asks for sudo when needed)."
command -v pacman >/dev/null || die "This installer is for Arch Linux (pacman not found)."
[[ -d $DOTS ]] || die "Can't find the dots folder. Run install.sh from inside the Lumi folder."

info "You'll be asked for your password so the installer can use sudo."
sudo -v || die "sudo failed. Is your user in the wheel group? See the README's Troubleshooting section."
# Keep sudo alive until the installer exits
(while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done) 2>/dev/null &
ok "Running as $USER with sudo"

if lspci 2>/dev/null | grep -qi 'vga.*nvidia\|3d.*nvidia'; then
    warn "NVIDIA GPU detected. If Hyprland shows a black screen, see 'NVIDIA' in the README."
fi

# ---------------------------------------------------------------------------
step "Checking the internet connection"

online() { curl -fsS --max-time 8 -o /dev/null https://archlinux.org; }

connect_wifi_nm() {
    sudo systemctl enable --now NetworkManager >/dev/null 2>&1 || true
    sleep 2
    nmcli radio wifi on >/dev/null 2>&1 || true
    info "Scanning for Wi-Fi networks..."
    nmcli device wifi rescan >/dev/null 2>&1 || true
    sleep 3
    nmcli -f SSID,SIGNAL,SECURITY device wifi list 2>/dev/null | head -n 15 || true
    local ssid pass
    read -r -p "  Wi-Fi name (SSID): " ssid </dev/tty
    read -r -s -p "  Password (leave empty for open networks): " pass </dev/tty
    echo
    if [[ -n $pass ]]; then
        nmcli device wifi connect "$ssid" password "$pass"
    else
        nmcli device wifi connect "$ssid"
    fi
}

connect_wifi_iwd() {
    sudo systemctl enable --now iwd >/dev/null 2>&1 || true
    sleep 2
    local dev ssid
    dev=$(iwctl device list 2>/dev/null | awk '/station/ {print $2; exit}')
    [[ -n $dev ]] || dev=wlan0
    info "Scanning for Wi-Fi networks on $dev..."
    iwctl station "$dev" scan || true
    sleep 3
    iwctl station "$dev" get-networks || true
    read -r -p "  Wi-Fi name (SSID): " ssid </dev/tty
    iwctl station "$dev" connect "$ssid"
}

if online; then
    ok "Online"
else
    warn "No internet connection."
    sudo rfkill unblock wifi 2>/dev/null || true
    for attempt in 1 2 3; do
        if command -v nmcli >/dev/null; then
            connect_wifi_nm || warn "Couldn't connect, check the name and password."
        elif command -v iwctl >/dev/null; then
            connect_wifi_iwd || warn "Couldn't connect, check the name and password."
        else
            die "No Wi-Fi tool found. Plug in ethernet, or see 'Connecting to the internet' in the README."
        fi
        sleep 4
        if online; then
            ok "Online"
            break
        fi
        ((attempt < 3)) && warn "Still offline, let's try again ($attempt/3)."
    done
    online || die "Still no internet. See 'Connecting to the internet' in the README."
fi

# ---------------------------------------------------------------------------
step "Updating the system"

info "A full update first avoids broken partial upgrades."
sudo pacman -Sy --noconfirm --needed archlinux-keyring
sudo pacman -Syu --noconfirm
ok "System up to date"

# ---------------------------------------------------------------------------
step "Installing packages"

sudo pacman -S --needed --noconfirm "${REPO_PKGS[@]}"
ok "Official packages installed"

AUR_HELPER=""
for helper in yay paru; do
    command -v "$helper" >/dev/null && AUR_HELPER=$helper && break
done
if [[ -z $AUR_HELPER ]]; then
    info "Installing yay (AUR helper)..."
    build_dir=$(mktemp -d)
    git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$build_dir/yay-bin"
    (cd "$build_dir/yay-bin" && makepkg -si --noconfirm)
    rm -rf "$build_dir"
    AUR_HELPER=yay
fi
ok "AUR helper: $AUR_HELPER"

info "Building AUR packages (quickshell compiles from source, this can take a while)..."
"$AUR_HELPER" -S --needed --noconfirm --answerdiff None --answerclean None "${AUR_PKGS[@]}" 2>/dev/null ||
    "$AUR_HELPER" -S --needed --noconfirm "${AUR_PKGS[@]}"
ok "AUR packages installed"

# ---------------------------------------------------------------------------
step "Building and installing the Lumi shell"

if [[ -d $SHELL_SRC/.git ]]; then
    git -C "$SHELL_SRC" pull --ff-only
else
    mkdir -p "$(dirname "$SHELL_SRC")"
    git clone "$SHELL_REPO" "$SHELL_SRC"
fi
(cd "$SHELL_SRC/packaging/arch" && makepkg -si --noconfirm --needed)
command -v lumi >/dev/null || die "The lumi command wasn't installed."
ok "Lumi shell installed ($(pacman -Q lumi-shell))"

# ---------------------------------------------------------------------------
step "Installing the desktop configuration"

# backup <path>: move an existing file/folder into the backup folder
backup() {
    local path=$1
    [[ -e $path ]] || return 0
    local rel=${path#"$HOME"/}
    mkdir -p "$BACKUP/$(dirname "$rel")"
    cp -a "$path" "$BACKUP/$rel"
}

install_dir() { # install_dir <src> <dst>: replace dst with src (after backup)
    backup "$2"
    mkdir -p "$(dirname "$2")"
    # Copy next to it first, so a failed copy never leaves you without a config
    rm -rf "$2.lumi-new"
    cp -a "$1" "$2.lumi-new"
    rm -rf "$2"
    mv "$2.lumi-new" "$2"
}

install_file() { # install_file <src> <dst>
    backup "$2"
    mkdir -p "$(dirname "$2")"
    cp -a "$1" "$2"
}

install_dir "$DOTS/hypr" "$CONFIG/hypr"
install_file "$DOTS/foot/foot.ini" "$CONFIG/foot/foot.ini"
install_file "$DOTS/fish/config.fish" "$CONFIG/fish/config.fish"
for f in "$DOTS"/fish/functions/*.fish; do
    install_file "$f" "$CONFIG/fish/functions/$(basename "$f")"
done
install_file "$DOTS/starship.toml" "$CONFIG/starship.toml"
install_file "$DOTS/qtengine/config.json" "$CONFIG/qtengine/config.json"

# Lumi's own settings: merged file by file, so secrets like tor-control.key stay put
for f in "$DOTS"/lumi/*; do
    install_file "$f" "$CONFIG/lumi/$(basename "$f")"
done
chmod +x "$CONFIG/lumi/projector.sh"

# Thunar: mount drives and media automatically when they're plugged in
if command -v xfconf-query >/dev/null; then
    for prop in /automount-drives/enabled /automount-media/enabled; do
        xfconf-query -c thunar-volman -p "$prop" -n -t bool -s true 2>/dev/null ||
            xfconf-query -c thunar-volman -p "$prop" -s true 2>/dev/null || true
    done
fi

[[ -d $BACKUP ]] && ok "Previous configs backed up to $BACKUP"
ok "Configuration installed"

# Wallpapers folder with the Lumi wallpaper in it
xdg-user-dirs-update 2>/dev/null || true
PICTURES=$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")
mkdir -p "$PICTURES/Wallpapers" "$PICTURES/Live-Wallpapers"
cp -n /etc/xdg/quickshell/lumi/assets/wallpaper.webp "$PICTURES/Wallpapers/lumi.webp" 2>/dev/null || true
ok "Wallpapers go in $PICTURES/Wallpapers (videos in Live-Wallpapers)"

# ---------------------------------------------------------------------------
step "Enabling services"

sudo systemctl enable --now NetworkManager.service
sudo systemctl enable --now bluetooth.service
sudo systemctl enable --now power-profiles-daemon.service
# A standalone iwd fights NetworkManager over Wi-Fi, but NetworkManager can also use
# iwd as its Wi-Fi backend (an archinstall option); then iwd must keep running
if grep -rqs '^\s*wifi\.backend\s*=\s*iwd' /etc/NetworkManager/NetworkManager.conf /etc/NetworkManager/conf.d/; then
    info "NetworkManager uses iwd for Wi-Fi, keeping iwd enabled"
elif systemctl is-enabled iwd.service >/dev/null 2>&1; then
    sudo systemctl disable --now iwd.service || true
    info "Disabled iwd (NetworkManager manages Wi-Fi now)"
fi
sudo rfkill unblock bluetooth wifi 2>/dev/null || true
ok "Wi-Fi, Bluetooth and power profiles enabled"

# ---------------------------------------------------------------------------
step "A few choices"

if [[ $SET_FISH == ask ]] && ask "Use fish as your shell (recommended, the prompt is designed for it)?" y; then
    SET_FISH=yes
fi
if [[ $SET_FISH == yes && $(getent passwd "$USER" | cut -d: -f7) != */fish ]]; then
    sudo chsh -s /usr/bin/fish "$USER"
    ok "fish is now your shell"
fi

if [[ $AUTOSTART == ask ]] && ask "Start Lumi automatically when you log in on the first console (tty1)?" y; then
    AUTOSTART=yes
fi
if [[ $AUTOSTART == yes ]]; then
    mkdir -p "$CONFIG/fish/conf.d"
    cat >"$CONFIG/fish/conf.d/lumi-autostart.fish" <<'EOF'
# Start Lumi (Hyprland) after logging in on tty1
if status is-login; and test -z "$WAYLAND_DISPLAY"; and test (tty) = /dev/tty1
    exec start-hyprland
end
EOF
    if ! grep -q 'lumi-autostart' "$HOME/.bash_profile" 2>/dev/null; then
        cat >>"$HOME/.bash_profile" <<'EOF'

# lumi-autostart: start Lumi (Hyprland) after logging in on tty1
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = /dev/tty1 ]; then
    exec start-hyprland
fi
EOF
    fi
    ok "Lumi will start after you log in on tty1"
fi

if [[ $TOR == ask ]] && ask "Set up Tor mode (IP rotation) and the firewall toggle?" n; then
    TOR=yes
fi
if [[ $TOR == yes ]]; then
    sudo lumi-tor-setup "$USER"
    ok "Tor mode and firewall ready (hover the shield in the bar)"
fi

# ---------------------------------------------------------------------------
step "Done"

cat <<EOF

  Lumi is installed.

  ${BOLD}Start it${RESET}
    - Reboot, then log in on the first console: Lumi starts by itself
      (or type ${BOLD}start-hyprland${RESET} if you skipped autostart).

  ${BOLD}First keys to try${RESET}
    SUPER            open the launcher
    SUPER + SPACE    pick a wallpaper (colours follow it)
    SUPER + T        terminal          SUPER + W   browser
    SUPER + 1..5     workspaces        SUPER + Q   close window
    CTRL + ALT + DEL session menu

  Full guide and troubleshooting: https://github.com/void193/Lumi
  Install log: $LOG

EOF
