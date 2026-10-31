#!/usr/bin/env bash
set -e

# === Configuration ===
REPO_URL="${REPO_URL:-https://github.com/versenilvis/Ambxst.git}"
BRANCH="${BRANCH:-main}"
INSTALL_PATH="${INSTALL_PATH:-$HOME/Ambxst}"
BIN_DIR="/usr/local/bin"
QUICKSHELL_REPO="https://git.outfoxxed.me/outfoxxed/quickshell"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check for root
if [ "$EUID" -eq 0 ]; then
	echo -e "${RED}✖  Please do not run this script as root.${NC}"
	echo -e "${YELLOW}   Use a normal user account. The script will use sudo where needed.${NC}"
	exit 1
fi

log_info() { echo -e "${BLUE}ℹ  $1${NC}"; }
log_success() { echo -e "${GREEN}✔  $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠  $1${NC}"; }
log_error() { echo -e "${RED}✖  $1${NC}"; }

# === Distro Detection ===
detect_distro() {
	if [ -f /etc/NIXOS ]; then
		echo "nixos"
	elif command -v pacman >/dev/null 2>&1; then
		echo "arch"
	elif command -v dnf >/dev/null 2>&1; then
		echo "fedora"
	elif command -v apt >/dev/null 2>&1; then
		echo "debian"
	else
		echo "unknown"
	fi
}

DISTRO=$(detect_distro)
log_info "Detected System: $DISTRO"

# === Dependency Definitions ===

# Common packages (Names might vary slightly, mapped below)
# Core: kitty, tmux, fuzzel, networkmanager, blueman, pulseaudio/pipewire tools
# Qt6: qt6-base, qt6-declarative, qt6-wayland, qt6-svg, qt6-tools
# Media: ffmpeg, playerctl, pipewire, wireplumber
# Tools: brightnessctl, ddcutil, jq, imagemagick, wl-clipboard, etc.

install_dependencies() {
	case "$DISTRO" in
	nixos)
		# Existing NixOS/Nix Logic (via flake)
		FLAKE_URI="${1:-github:versenilvis/Ambxst}"

		# Conflict cleanup logic from original script
		if nix profile list | grep -q "ddcutil"; then
			nix profile remove ddcutil 2>/dev/null || true
		fi

		if nix profile list | grep -q "Ambxst"; then
			log_info "Updating Ambxst..."
			nix profile upgrade Ambxst --refresh --impure
		else
			log_info "Installing Ambxst..."
			nix profile add "$FLAKE_URI" --impure
		fi
		;;

	fedora)
		log_info "Preparing installation for Fedora..."

		# Enable COPRs
		log_info "Enabling COPR repositories..."
		sudo dnf install -y dnf-plugins-core
		yes | sudo dnf copr enable errornointernet/quickshell
		yes | sudo dnf copr enable solopasha/hyprland
		yes | sudo dnf copr enable zirconium/packages
		yes | sudo dnf copr enable iucar/cran

		log_info "Installing dependencies..."

		PKGS=(
			# Apps
			kitty tmux fuzzel network-manager-applet blueman

			# Audio/Video
			pipewire wireplumber easyeffects playerctl pamixer

			# Qt6 & KDE deps
			qt6-qtbase qt6-qtdeclarative qt6-qtwayland qt6-qtsvg qt6-qttools
			qt6-qtimageformats qt6-qtmultimedia qt6-qtshadertools
			kf6-syntax-highlighting kf6-breeze-icons hicolor-icon-theme polkit-kde

			# Build & Backend
			rust cargo openssl-devel pkgconf-pkg-config

			# Tools
			brightnessctl ddcutil fontconfig grim slurp ImageMagick jq sqlite upower
			wl-clipboard wlsunset wtype zbar glib2 zenity power-profiles-daemon
			libnotify flatpak hyprpicker hypridle hyprlock

			# Tesseract
			tesseract tesseract-langpack-eng tesseract-langpack-spa tesseract-langpack-jpn
			tesseract-langpack-chi_sim tesseract-langpack-chi_tra tesseract-langpack-kor
			tesseract-langpack-lat

			# Fonts
			google-inter-fonts jetbrains-mono-fonts google-roboto-fonts google-roboto-mono-fonts
			dejavu-sans-fonts liberation-fonts google-noto-fonts-common google-noto-cjk-fonts
			google-noto-emoji-fonts

			# Special Packages
			mpvpaper matugen R-CRAN-phosphoricons adw-gtk3-theme

			# Quickshell
			quickshell-git

			# Utils
			unzip curl git
		)

		sudo dnf install -y "${PKGS[@]}"

		# Gradia (Flatpak)
		log_info "Installing Gradia (Flatpak)..."
		flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
		flatpak install -y flathub be.alexandervanhee.gradia

		# Manual install of Phosphor Icons
		log_info "Installing Phosphor Icons..."
		PHOSPHOR_VERSION="2.1.2"
		PHOSPHOR_URL="https://github.com/phosphor-icons/web/archive/refs/tags/v${PHOSPHOR_VERSION}.zip"
		TEMP_DIR="$(mktemp -d)"

		log_info "Downloading Phosphor Icons v${PHOSPHOR_VERSION}..."
		curl -L -o "$TEMP_DIR/phosphor.zip" "$PHOSPHOR_URL"

		log_info "Extracting..."
		unzip -q "$TEMP_DIR/phosphor.zip" -d "$TEMP_DIR"

		FONT_DIR="$HOME/.local/share/fonts/phosphor"
		mkdir -p "$FONT_DIR"
		find "$TEMP_DIR" -name "*.ttf" -exec cp {} "$FONT_DIR/" \;
		rm -rf "$TEMP_DIR"
		fc-cache -f "$FONT_DIR"
		log_success "Phosphor Icons installed to $FONT_DIR"
		;;

	arch)
		log_info "Preparing installation..."

		# Ensure git and base-devel are installed for AUR helper compilation
		if ! command -v git >/dev/null || ! command -v makepkg >/dev/null; then
			log_info "Installing git and base-devel (required for AUR helper)..."
			sudo pacman -S --needed --noconfirm git base-devel
		fi

		# Check for AUR helpers
		AUR_HELPER=""
		if command -v yay >/dev/null; then
			AUR_HELPER="yay"
		elif command -v paru >/dev/null; then
			AUR_HELPER="paru"
		else
			log_info "No AUR helper found. Installing yay-bin..."
			YAY_TMP="$(mktemp -d)"
			git clone "https://aur.archlinux.org/yay-bin.git" "$YAY_TMP"
			pushd "$YAY_TMP"
			makepkg -si --noconfirm
			popd
			rm -rf "$YAY_TMP"
			AUR_HELPER="yay"
		fi

		log_info "Installing dependencies with $AUR_HELPER..."

		PKGS=(
			# Apps
			kitty tmux fuzzel network-manager-applet blueman

			# Audio/Video
			pipewire wireplumber pwvucontrol easyeffects ffmpeg x264 playerctl pamixer

			# Qt6 & KDE deps
			qt6-base qt6-declarative qt6-wayland qt6-svg qt6-tools qt6-imageformats qt6-multimedia qt6-shadertools
			libwebp libavif
			syntax-highlighting breeze-icons hicolor-icon-theme polkit-kde-agent

			# Build & Backend
			rust cargo openssl pkgconf

			# Tools
			brightnessctl ddcutil fontconfig grim slurp imagemagick jq sqlite upower
			wl-clipboard cliphist wlsunset wtype zbar glib2 zenity inetutils power-profiles-daemon
			libnotify

			# Hyprland & Wayland tools
			hyprpicker hypridle hyprlock grimblast-git

			# Tesseract
			tesseract tesseract-data-eng tesseract-data-spa tesseract-data-jpn tesseract-data-chi_sim tesseract-data-chi_tra tesseract-data-kor tesseract-data-lat

			# Fonts
			inter-font ttf-jetbrains-mono ttf-roboto ttf-roboto-mono ttf-dejavu ttf-liberation noto-fonts noto-fonts-cjk noto-fonts-emoji
			ttf-nerd-fonts-symbols

			# Special Packages
			matugen gpu-screen-recorder wl-clip-persist mpvpaper gradia
			quickshell-git ttf-phosphor-icons ttf-league-gothic adw-gtk-theme
		)

		$AUR_HELPER -S --needed --noconfirm "${PKGS[@]}"
		;;

	*)
		log_error "Unsupported distribution for automatic dependency installation: $DISTRO"
		log_warn "Please ensure you have all dependencies listed in nix/packages/ installed."
		;;
	esac
}

# === Ambxst Clone ===
setup_repo() {
	if [ "$DISTRO" != "nixos" ]; then
		# check if running from within an existing clone
		SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
		if [ -f "$SCRIPT_DIR/shell.qml" ] && [ -d "$SCRIPT_DIR/.git" ]; then
			INSTALL_PATH="$SCRIPT_DIR"
			log_info "Using current Ambxst directory at $INSTALL_PATH"
			return
		fi

		if [ ! -d "$INSTALL_PATH" ]; then
			log_info "Cloning Ambxst ($BRANCH) to $INSTALL_PATH..."
			git clone -b "$BRANCH" "$REPO_URL" "$INSTALL_PATH"
		else
			log_info "Ambxst directory exists. Checking status..."
			git -C "$INSTALL_PATH" fetch origin "$BRANCH" 2>/dev/null || git -C "$INSTALL_PATH" fetch origin

			CURRENT_BRANCH=$(git -C "$INSTALL_PATH" rev-parse --abbrev-ref HEAD)
			if [ "$CURRENT_BRANCH" == "$BRANCH" ]; then
				# check for local changes (uncommitted or committed ahead of origin)
				HAS_CHANGES=0
				if [ -n "$(git -C "$INSTALL_PATH" status --porcelain)" ]; then HAS_CHANGES=1; fi
				if [ -n "$(git -C "$INSTALL_PATH" log "origin/$BRANCH..HEAD" 2>/dev/null)" ]; then HAS_CHANGES=1; fi

				if [ "$HAS_CHANGES" -eq 1 ]; then
					echo -e "${YELLOW}⚠  Local changes or custom commits detected on '$BRANCH'.${NC}"
					echo -e "${RED}This update will DISCARD all your local changes to match the remote.${NC}"
					echo -e "Make sure to save your changes in another branch if needed."
					read -r -p "Continue and overwrite local changes? [y/N] " response </dev/tty
					if [[ ! "$response" =~ ^[Yy]$ ]]; then
						log_warn "Update aborted by user to protect local changes."
						exit 0
					fi
				fi

				log_info "Enforcing remote state..."
				git -C "$INSTALL_PATH" reset --hard "origin/$BRANCH"
			else
				log_warn "Your Ambxst installation is on branch '$CURRENT_BRANCH', not '$BRANCH'."
				log_warn "Automatic update skipped to protect your changes. Switch to '$BRANCH' to update."
			fi
		fi
	fi
}

# === Ambxst Daemon Build (Rust) ===
build_daemon() {
	if [ "$DISTRO" == "nixos" ]; then return; fi

	log_info "Building ambxst-daemon (Rust backend)..."

	if ! command -v cargo >/dev/null 2>&1; then
		if [ -f "$HOME/.cargo/bin/cargo" ]; then
			export PATH="$HOME/.cargo/bin:$PATH"
		else
			log_error "cargo not found. Please install Rust (https://rustup.rs) to build ambxst-daemon."
			return 1
		fi
	fi

	pushd "$INSTALL_PATH/ambxst-daemon" >/dev/null
	cargo build --release
	popd >/dev/null

	mkdir -p "$INSTALL_PATH/bin"
	install -m 755 "$INSTALL_PATH/ambxst-daemon/target/release/ambxst-daemon" "$INSTALL_PATH/bin/ambxst-daemon"
	chmod +x "$INSTALL_PATH/cli.sh" "$INSTALL_PATH/scripts/"*.sh 2>/dev/null || true
	log_success "ambxst-daemon compiled and installed to $INSTALL_PATH/bin/ambxst-daemon"
}

# === Quickshell Build (Git) ===
install_quickshell() {
	if [ "$DISTRO" == "nixos" ] || [ "$DISTRO" == "fedora" ]; then return; fi # NixOS installs via flake, Fedora via COPR

	if ! command -v qs >/dev/null; then
		log_info "Building Quickshell from source..."

		QS_BUILD_DIR="$(mktemp -d)"
		git clone --recursive "$QUICKSHELL_REPO" "$QS_BUILD_DIR"

		pushd "$QS_BUILD_DIR"
		cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$HOME/.local"
		cmake --build build
		cmake --install build
		popd
		rm -rf "$QS_BUILD_DIR"

		log_success "Quickshell installed to ~/.local/bin/qs"
	else
		log_info "Quickshell (qs) is already installed."
	fi
}

# === Service Configuration ===
configure_services() {
	if [ "$DISTRO" == "nixos" ]; then return; fi

	log_info "Configuring system services..."

	if command -v systemctl >/dev/null; then
		log_info "Detected Init System: systemd"

		# Disable iwd if active/enabled to prevent conflicts
		if systemctl is-enabled --quiet iwd 2>/dev/null || systemctl is-active --quiet iwd 2>/dev/null; then
			log_warn "Disabling iwd to prevent conflicts with NetworkManager..."
			sudo systemctl stop iwd
			sudo systemctl disable iwd
		fi

		# Enable NetworkManager
		if ! systemctl is-enabled --quiet NetworkManager 2>/dev/null; then
			log_info "Enabling and starting NetworkManager..."
			sudo systemctl enable --now NetworkManager
			log_success "NetworkManager enabled."
		else
			log_info "NetworkManager is already enabled."
		fi

		# Enable Bluetooth
		if ! systemctl is-enabled --quiet bluetooth 2>/dev/null; then
			log_info "Enabling and starting Bluetooth..."
			sudo systemctl enable --now bluetooth
			log_success "Bluetooth enabled."
		else
			log_info "Bluetooth is already enabled."
		fi

	elif command -v rc-service >/dev/null; then
		log_info "Detected Init System: OpenRC"

		# Disable iwd
		if rc-update show | grep -q "iwd"; then
			log_warn "Disabling iwd..."
			sudo rc-service iwd stop 2>/dev/null || true
			sudo rc-update del iwd default 2>/dev/null || true
		fi

		# Enable NetworkManager
		log_info "Enabling NetworkManager..."
		sudo rc-update add NetworkManager default 2>/dev/null || true
		sudo rc-service NetworkManager start 2>/dev/null || true

		# Enable Bluetooth
		log_info "Enabling Bluetooth..."
		sudo rc-update add bluetooth default 2>/dev/null || true
		sudo rc-service bluetooth start 2>/dev/null || true

	elif command -v sv >/dev/null; then
		log_info "Detected Init System: Runit"
		SERVICE_DIR="/var/service"

		# Disable iwd
		if [ -L "$SERVICE_DIR/iwd" ]; then
			log_warn "Disabling iwd..."
			sudo rm "$SERVICE_DIR/iwd"
		fi

		# Enable NetworkManager
		if [ -d "/etc/sv/NetworkManager" ] && [ ! -L "$SERVICE_DIR/NetworkManager" ]; then
			log_info "Enabling NetworkManager..."
			sudo ln -s /etc/sv/NetworkManager "$SERVICE_DIR/"
		fi

		# Enable Bluetooth
		if [ -d "/etc/sv/bluetooth" ] && [ ! -L "$SERVICE_DIR/bluetooth" ]; then
			log_info "Enabling Bluetooth..."
			sudo ln -s /etc/sv/bluetooth "$SERVICE_DIR/"
		fi

	else
		log_warn "Could not detect a supported init system (systemd, openrc, runit)."
		log_warn "Please manually enable NetworkManager and Bluetooth."
	fi
}

# === Launcher Setup ===
setup_launcher() {
	if [ "$DISTRO" == "nixos" ]; then return; fi

	# User launcher in ~/.local/bin
	mkdir -p "$HOME/.local/bin"
	ln -sf "$INSTALL_PATH/cli.sh" "$HOME/.local/bin/ambxst"
	chmod +x "$HOME/.local/bin/ambxst"

	# System launcher in /usr/local/bin
	mkdir -p "$BIN_DIR" 2>/dev/null || sudo mkdir -p "$BIN_DIR"
	LAUNCHER="$BIN_DIR/ambxst"

	log_info "Creating launcher at $LAUNCHER..."

	sudo tee "$LAUNCHER" >/dev/null <<EOF
#!/usr/bin/env bash
export PATH="\$HOME/.local/bin:\$PATH"
export QML2_IMPORT_PATH="\$HOME/.local/lib/qml:\$QML2_IMPORT_PATH"
export QML_IMPORT_PATH="\$QML2_IMPORT_PATH"

# Execute the CLI script from the repo
exec "$INSTALL_PATH/cli.sh" "\$@"
EOF

	sudo chmod +x "$LAUNCHER"
	log_success "Launcher created at $LAUNCHER and $HOME/.local/bin/ambxst"
}

# === Main Execution ===

# 1. Install Dependencies
install_dependencies "$1"

# 2. Setup Repo (Non-NixOS)
setup_repo

# 3. Build Ambxst Daemon (Rust backend)
build_daemon

# 4. Install Quickshell (Non-NixOS)
install_quickshell

# 5. Configure Services
configure_services

# 6. Setup Launcher
setup_launcher

echo ""
log_success "Installation steps completed!"
if [ "$DISTRO" != "nixos" ]; then
	echo -e "Run ${GREEN}ambxst${NC} to start."
fi
