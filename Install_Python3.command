#!/bin/bash
# Copyright (c) 2024-2025, LongQT-sea
# macOS Python3 Silent Installer
# Installs appropriate Python3 version based on macOS version
# Checks if installer exists in current directory first; if not, downloads from python.org
# Supports macOS 10.6 and later

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" >&2; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

if [ "$EUID" -ne 0 ]; then
    echo ""
    echo -e "${YELLOW}[INFO]${NC} Administrator privileges required..."
    exec sudo "$0" "$@"
    exit
fi

API_URL="https://www.python.org/api/v2/downloads/release/?version=3&pre_release=false&is_published=true"

get_macos_version() {
    sw_vers -productVersion
}

fetch_url() {
    [ -z "$1" ] && return 1
    if command -v curl >/dev/null 2>&1; then
        curl -sfL --connect-timeout 10 --max-time 20 "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- --timeout=20 "$1"
    else
        return 1
    fi
}

get_latest_version() {
    local branch="$1" fallback="$2" raw="" latest="" filter='^[0-9]+\.[0-9]+\.[0-9]+$'

    [ -n "$branch" ] && filter="^${branch//./\\.}\\.[0-9]+$"

    raw="$(fetch_url "$API_URL" || true)"
    if [ -n "$raw" ]; then
        latest="$(printf '%s' "$raw" \
            | grep -oE '"name"[[:space:]]*:[[:space:]]*"Python [0-9][^"]*"' \
            | sed -E 's/.*"Python //; s/"$//' \
            | grep -E "$filter" \
            | sort -t. -k1,1n -k2,2n -k3,3n \
            | tail -n 1)"
    fi

    if [ -n "$latest" ]; then
        echo "$latest"
    elif [ -n "$fallback" ]; then
        print_warning "Version lookup failed. Using fallback: $fallback"
        echo "$fallback"
    else
        return 1
    fi
}

determine_python_version() {
    local macos_version=$1
    local major
    local minor
    major=$(echo "$macos_version" | cut -d. -f1)
    minor=$(echo "$macos_version" | cut -d. -f2)

    if [ "$major" -eq 10 ]; then
        if [ "$minor" -ge 15 ]; then
            print_info "Fetching latest Python 3 release..."
            PYTHON_VERSION=$(get_latest_version "" "3.14.7")
            PYTHON_PKG="python-${PYTHON_VERSION}-macos11.pkg"
            DOWNLOAD_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/${PYTHON_PKG}"
        elif [ "$minor" -ge 13 ] && [ "$minor" -le 14 ]; then
            # 3.13 is the last branch supporting macOS 10.13-10.14
            print_info "Fetching latest Python 3.13 release..."
            PYTHON_VERSION=$(get_latest_version "3.13" "3.13.12")
            PYTHON_PKG="python-${PYTHON_VERSION}-macos11.pkg"
            DOWNLOAD_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/${PYTHON_PKG}"
        elif [ "$minor" -ge 9 ] && [ "$minor" -le 12 ]; then
            # EOL — 3.9.13 is the last release with a macosx10.9 pkg
            PYTHON_VERSION="3.9.13"
            PYTHON_PKG="python-3.9.13-macosx10.9.pkg"
            DOWNLOAD_URL="https://www.python.org/ftp/python/3.9.13/${PYTHON_PKG}"
        elif [ "$minor" -ge 6 ] && [ "$minor" -le 8 ]; then
            # EOL — 3.6.8 is the last release with a macosx10.6 pkg
            PYTHON_VERSION="3.6.8"
            PYTHON_PKG="python-3.6.8-macosx10.6.pkg"
            DOWNLOAD_URL="https://www.python.org/ftp/python/3.6.8/${PYTHON_PKG}"
        else
            print_error "Unsupported macOS version: $macos_version"
            exit 1
        fi
    elif [ "$major" -ge 11 ]; then
        print_info "Fetching latest Python 3 release..."
        PYTHON_VERSION=$(get_latest_version "" "3.14.7")
        PYTHON_PKG="python-${PYTHON_VERSION}-macos11.pkg"
        DOWNLOAD_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/${PYTHON_PKG}"
    else
        print_error "Unsupported macOS version: $macos_version"
        exit 1
    fi
}

find_pkg_in_dir() {
    local dir=$1
    local f
    for f in "$dir"/python-"${PYTHON_VERSION}"*.pkg; do
        if [ -f "$f" ]; then
            echo "$f"
            return 0
        fi
    done
    return 1
}

check_local_installer() {
    local script_dir
    local current_dir
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    current_dir="$(pwd)"
    local found
    if found=$(find_pkg_in_dir "$script_dir"); then
        echo "$found"
        return 0
    fi
    if [ "$current_dir" != "$script_dir" ]; then
        if found=$(find_pkg_in_dir "$current_dir"); then
            echo "$found"
            return 0
        fi
    fi
    return 1
}

download_installer() {
    local url=$1
    local output=$2
    print_info "Downloading Python installer from: $url"
    if command -v curl >/dev/null 2>&1; then
        curl -fL -o "$output" "$url" --connect-timeout 30 --max-time 600 || {
            rm -f "$output"
            return 1
        }
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$output" "$url" --timeout=30 || {
            rm -f "$output"
            return 1
        }
    else
        print_error "Neither curl nor wget found. Cannot download installer."
        return 1
    fi
}

install_python() {
    local pkg_path=$1
    print_info "Installing Python from: $pkg_path"
    if [ ! -f "$pkg_path" ]; then
        print_error "Installer file not found: $pkg_path"
        exit 1
    fi
    if installer -pkg "$pkg_path" -target / -verbose; then
        print_info "Python installed successfully!"
    else
        print_error "Installation failed!"
        return 1
    fi
}

install_certificates() {
    local vers_folder
    vers_folder="Python $(echo "$PYTHON_VERSION" | cut -d. -f1,2)"
    if [ -f "/Applications/$vers_folder/Install Certificates.command" ]; then
        print_info "Updating certificates..."
        "/Applications/$vers_folder/Install Certificates.command" || \
            print_warning "Certificate update failed; pip/ssl may not verify HTTPS."
    else
        print_warning "Install Certificates.command not found for $vers_folder."
    fi
}

main() {
    print_info "macOS Python Silent Installer"
    echo ""

    local MACOS_VERSION
    MACOS_VERSION=$(get_macos_version)
    print_info "Detected macOS version: $MACOS_VERSION"

    determine_python_version "$MACOS_VERSION"
    print_info "Target Python version: $PYTHON_VERSION"
    print_info "Installer package: $PYTHON_PKG"
    echo ""

    print_info "Checking for local installer..."
    print_info "Script directory: $(cd "$(dirname "$0")" && pwd)"
    print_info "Current directory: $(pwd)"

    local INSTALLER_PATH
    local LOCAL_PKG
    if LOCAL_PKG=$(check_local_installer); then
        print_info "Found local installer: $LOCAL_PKG"
        INSTALLER_PATH="$LOCAL_PKG"
    else
        print_warning "Local installer not found. Attempting to download..."
        local DOWNLOADS_DIR
        if [ -n "$SUDO_USER" ]; then
            DOWNLOADS_DIR="$(eval echo "~$SUDO_USER")/Downloads"
        else
            DOWNLOADS_DIR="$HOME/Downloads"
        fi
        mkdir -p "$DOWNLOADS_DIR"
        INSTALLER_PATH="$DOWNLOADS_DIR/$PYTHON_PKG"
        print_info "Will save installer to: $INSTALLER_PATH"

        if ! download_installer "$DOWNLOAD_URL" "$INSTALLER_PATH"; then
            print_error "Download failed!"
            echo ""
            print_warning "This may be due to outdated SSL/TLS support on older macOS versions."
            print_warning "Please try one of the following options:"
            echo "  1. Download the installer on a newer macOS system and transfer it here"
            echo "  2. Download manually from: $DOWNLOAD_URL"
            echo "  3. Place the installer in the same directory as this script and run again"
            echo ""
            print_info "Looking for: $PYTHON_PKG"
            exit 1
        fi
        print_info "Download completed successfully!"
    fi

    echo ""
    if install_python "$INSTALLER_PATH"; then
        install_certificates
        echo ""
        print_info "Installation complete!"
        if command -v python3 >/dev/null 2>&1; then
            local INSTALLED_VERSION
            INSTALLED_VERSION=$(python3 --version 2>&1)
            print_info "Installed: $INSTALLED_VERSION"
        fi
    else
        exit 1
    fi
}

main
exit 0