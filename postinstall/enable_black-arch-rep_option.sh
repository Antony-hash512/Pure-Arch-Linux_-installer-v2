#!/bin/bash

# ==============================================================================
# BlackArch Repository Installer
#
# DESCRIPTION:
# This script securely downloads and installs the BlackArch Linux repository.
#
# IMPORTANT / NOTE:
# This is an OPTIONAL component. It is intended to be used as an add-on to a
# standard Arch Linux installation. This script should only be executed if
# the user explicitly chooses to enable BlackArch tools.
#
# ==============================================================================

# Stop script on any error
set -e

# Constants
URL_SCRIPT="https://blackarch.org/strap.sh"
URL_SIG="https://blackarch.org/strap.sh.sig"
# Fingerprint of Levon 'noptrix' Kayan's key (BlackArch Creator)
GPG_KEY_ID="4345771566D76038C7FEB43863EC0ADBEA87E4E3"

# 0. Check and install dependencies
echo ":: Checking dependencies..."
# -S: install
# -y: refresh package databases (to avoid 404 on old versions)
# --needed: install package only if it is not already installed
# --noconfirm: do not ask for confirmation (y/n)
sudo pacman -Sy --needed --noconfirm curl gnupg

echo ":: [BlackArch Installer] Initialization..."

# 1. Create a secure temporary directory
# mktemp -d creates a unique dir in /tmp with restricted permissions
WORK_DIR=$(mktemp -d)
echo "-> Created temporary directory: $WORK_DIR"

# 2. Set up trap for cleanup
# Ensures cleanup happens on exit or error
trap "rm -rf '$WORK_DIR'; echo '-> Temporary files cleaned up.'" EXIT

# 3. Download script and signature
echo ":: Downloading strap.sh and signature..."
curl -fsSL "$URL_SCRIPT" -o "$WORK_DIR/strap.sh"
curl -fsSL "$URL_SIG"    -o "$WORK_DIR/strap.sh.sig"

# 4. GPG verification
echo ":: Verifying GPG signature..."

# Import developer key
gpg --keyserver keyserver.ubuntu.com --recv-keys "$GPG_KEY_ID" > /dev/null 2>&1 || true

# Verify file signature
if gpg --quiet --verify "$WORK_DIR/strap.sh.sig" "$WORK_DIR/strap.sh"; then
    echo "-> [SUCCESS] Signature is valid. Script is authentic."
else
    echo "-> [ERROR] Invalid GPG signature! Aborting."
    exit 1
fi

# 5. Start installation
echo ":: Starting installation (sudo privileges required)..."
chmod +x "$WORK_DIR/strap.sh"
sudo "$WORK_DIR/strap.sh"

echo ":: Done! BlackArch repository enabled."