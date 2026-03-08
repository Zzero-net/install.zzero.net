#!/bin/sh
# Zero Network Node Installer
# https://install.zzero.net
#
# Usage:
#   curl -sSf https://install.zzero.net/install.sh | sh
#
# This script detects your OS and architecture, downloads the correct
# zero-node binary, and installs it to your system.

set -e

# Colors (matching Zero Network green theme)
GREEN='\033[0;38;2;0;255;65m'
CYAN='\033[0;38;2;0;212;255m'
AMBER='\033[0;38;2;255;176;0m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

VERSION="v0.1.0-testnet"
BASE_URL="https://github.com/Zzero-net/install.zzero.net/releases/download"

# ─── Helpers ─────────────────────────────────────────────────────────

info() {
    printf "${GREEN}[zero]${RESET} %s\n" "$1"
}

warn() {
    printf "${AMBER}[warn]${RESET} %s\n" "$1"
}

error() {
    printf "${RED}[error]${RESET} %s\n" "$1" >&2
    exit 1
}

banner() {
    printf "\n"
    printf "${GREEN}${BOLD}"
    printf "  ╔══════════════════════════════════════╗\n"
    printf "  ║       Zero Network Node Install      ║\n"
    printf "  ║            %s             ║\n" "$VERSION"
    printf "  ╚══════════════════════════════════════╝\n"
    printf "${RESET}\n"
}

# ─── Detect Platform ─────────────────────────────────────────────────

detect_os() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "darwin" ;;
        *)       error "Unsupported operating system: $(uname -s). Only Linux and macOS are supported." ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)   echo "amd64" ;;
        aarch64|arm64)  echo "arm64" ;;
        *)              error "Unsupported architecture: $(uname -m). Only x86_64 and arm64 are supported." ;;
    esac
}

# ─── Check Dependencies ─────────────────────────────────────────────

check_deps() {
    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER="curl"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget"
    else
        error "Neither curl nor wget found. Please install one and try again."
    fi
}

download() {
    local url="$1"
    local output="$2"
    if [ "$DOWNLOADER" = "curl" ]; then
        curl -fsSL --progress-bar -o "$output" "$url"
    else
        wget -q --show-progress -O "$output" "$url"
    fi
}

# ─── Determine Install Directory ────────────────────────────────────

get_install_dir() {
    if [ "$(id -u)" -eq 0 ]; then
        echo "/usr/local/bin"
    elif [ -d "$HOME/.local/bin" ] || mkdir -p "$HOME/.local/bin" 2>/dev/null; then
        echo "$HOME/.local/bin"
    else
        error "Cannot determine install directory. Run as root or ensure ~/.local/bin exists."
    fi
}

check_path() {
    local dir="$1"
    case ":$PATH:" in
        *":$dir:"*) ;;
        *)
            warn "$dir is not in your PATH."
            printf "${DIM}  Add it by running:${RESET}\n"
            if [ -f "$HOME/.zshrc" ]; then
                printf "${CYAN}    echo 'export PATH=\"%s:\$PATH\"' >> ~/.zshrc && source ~/.zshrc${RESET}\n" "$dir"
            else
                printf "${CYAN}    echo 'export PATH=\"%s:\$PATH\"' >> ~/.bashrc && source ~/.bashrc${RESET}\n" "$dir"
            fi
            printf "\n"
            ;;
    esac
}

# ─── Create Data Directory ───────────────────────────────────────────

create_data_dir() {
    local data_dir="/opt/zero/data"

    if [ "$(id -u)" -eq 0 ]; then
        if [ ! -d "$data_dir" ]; then
            mkdir -p "$data_dir"
            info "Created data directory: $data_dir"
        fi
    else
        if [ ! -d "$data_dir" ]; then
            if mkdir -p "$data_dir" 2>/dev/null; then
                info "Created data directory: $data_dir"
            else
                local alt_dir="$HOME/.zero/data"
                mkdir -p "$alt_dir"
                info "Created data directory: $alt_dir (no root access for /opt/zero)"
                warn "Update data_dir in your zero.toml to: $alt_dir"
            fi
        fi
    fi
}

# ─── Main Install ────────────────────────────────────────────────────

main() {
    banner

    # Detect platform
    local os arch
    os="$(detect_os)"
    arch="$(detect_arch)"
    info "Detected platform: ${os}/${arch}"

    # Check download tool
    check_deps

    # Build download URL
    local binary_name="zero-node-${os}-${arch}"
    local download_url="${BASE_URL}/${VERSION}/${binary_name}"
    info "Downloading ${binary_name} (${VERSION})..."

    # Create temp directory
    local tmp_dir
    tmp_dir="$(mktemp -d)" || error "Failed to create temporary directory."
    trap 'rm -rf "$tmp_dir"' EXIT

    # Download binary
    local tmp_bin="${tmp_dir}/zero-node"
    if ! download "$download_url" "$tmp_bin"; then
        error "Download failed. Please check your internet connection and try again.
  URL: $download_url

  Note: ${VERSION} binaries may not be available yet.
  Visit https://install.zzero.net for manual download options."
    fi

    # Verify download is not empty
    if [ ! -s "$tmp_bin" ]; then
        error "Downloaded file is empty. The binary may not be available yet for ${os}/${arch}."
    fi

    # Make executable
    chmod +x "$tmp_bin"

    # Determine install location
    local install_dir
    install_dir="$(get_install_dir)"
    local install_path="${install_dir}/zero-node"

    # Check for existing installation
    if [ -f "$install_path" ]; then
        local existing_version
        existing_version="$("$install_path" --version 2>/dev/null || echo "unknown")"
        warn "Existing installation found: $existing_version"
        info "Upgrading to ${VERSION}..."
    fi

    # Install binary
    if [ "$(id -u)" -eq 0 ]; then
        mv "$tmp_bin" "$install_path"
    else
        if [ "$install_dir" = "/usr/local/bin" ]; then
            error "Cannot write to /usr/local/bin without root. Run with sudo or install to ~/.local/bin."
        fi
        mv "$tmp_bin" "$install_path"
    fi

    info "Installed to: ${install_path}"

    # Create data directory
    create_data_dir

    # Verify installation
    if command -v zero-node >/dev/null 2>&1; then
        info "Installation verified."
    else
        check_path "$install_dir"
    fi

    # Success message
    printf "\n"
    printf "${GREEN}${BOLD}  ✓ Zero Node installed successfully!${RESET}\n"
    printf "\n"
    printf "${DIM}  ── Next Steps ──────────────────────────────────${RESET}\n"
    printf "\n"
    printf "  ${CYAN}1.${RESET} Initialize your validator node:\n"
    printf "     ${GREEN}\$ zero-node init --validator${RESET}\n"
    printf "\n"
    printf "  ${CYAN}2.${RESET} Edit your configuration:\n"
    printf "     ${GREEN}\$ nano /opt/zero/zero.toml${RESET}\n"
    printf "\n"
    printf "  ${CYAN}3.${RESET} Start your node:\n"
    printf "     ${GREEN}\$ zero-node run${RESET}\n"
    printf "\n"
    printf "  ${CYAN}4.${RESET} Check node status:\n"
    printf "     ${GREEN}\$ zero-node status${RESET}\n"
    printf "\n"
    printf "${DIM}  ── Resources ───────────────────────────────────${RESET}\n"
    printf "\n"
    printf "  Docs:      ${CYAN}https://docs.zzero.net${RESET}\n"
    printf "  Explorer:  ${CYAN}https://explorer.zzero.net${RESET}\n"
    printf "  GitHub:    ${CYAN}https://github.com/Zzero-net${RESET}\n"
    printf "\n"
}

main "$@"
