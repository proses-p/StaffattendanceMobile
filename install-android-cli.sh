#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# === Configuration ===
BINARY_NAME="android"
INSTALL_DIR="$HOME/.local/bin"

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS $ARCH" in
    "Linux x86_64") URL_OS="linux_x86_64" ;;
    "Linux aarch64") URL_OS="linux_arm64" ;;
    "Darwin x86_64") URL_OS="darwin_x86_64" ;;
    "Darwin arm64") URL_OS="darwin_arm64" ;;
    *) echo "Error: unrecognized OS or CPU: $OS $ARCH" >&2; exit 1;;
esac

DOWNLOAD_URL="https://dl.google.com/android/cli/latest/${URL_OS}/${BINARY_NAME}"

# 1. Check if curl is installed
if ! command -v curl &> /dev/null; then
    echo "Error: curl is required to install or upgrade this software."
    exit 1
fi

echo "Installing $BINARY_NAME..."

# Ensure install directory exists
mkdir -p "$INSTALL_DIR"

# 2. Download the binary
TMP_FILE=$(mktemp)
trap 'rm -f "$TMP_FILE"' EXIT

echo "Downloading..."
curl -fsSL "$DOWNLOAD_URL" -o "$TMP_FILE"

# 3. Move to the local path and make executable
echo "Installing to $INSTALL_DIR..."
mv "$TMP_FILE" "${INSTALL_DIR}/${BINARY_NAME}"
chmod +x "${INSTALL_DIR}/${BINARY_NAME}"

# 4. Attempt to add to PATH if not already there
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    PROFILE_FILES=()
    
    if [[ "$SHELL" == *"zsh"* ]]; then
        PROFILE_FILES=("$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.zshenv")
    elif [[ "$SHELL" == *"bash"* ]]; then
        if [[ "$OS" == "Darwin" ]]; then
            PROFILE_FILES=("$HOME/.bash_profile" "$HOME/.profile" "$HOME/.bashrc")
        else
            PROFILE_FILES=("$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile")
        fi
    else
        PROFILE_FILES=("$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc")
    fi

    CONFIG_FILE=""
    for file in "${PROFILE_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            CONFIG_FILE="$file"
            break
        fi
    done

    if [[ -z "$CONFIG_FILE" ]]; then
        # Create the most appropriate one based on current shell
        CONFIG_FILE="${PROFILE_FILES[0]}"
    fi

    if touch "$CONFIG_FILE" 2>/dev/null; then
        if ! grep -q "$INSTALL_DIR" "$CONFIG_FILE" 2>/dev/null; then
            echo -e "\n# Added by Android CLI installer" >> "$CONFIG_FILE"
            echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$CONFIG_FILE"
            echo "Added $INSTALL_DIR to PATH in $CONFIG_FILE"
            echo "Please run 'source $CONFIG_FILE' or restart your terminal to apply."
        else
            echo "Note: $INSTALL_DIR is already in $CONFIG_FILE, but not in your current PATH."
            echo "Please run 'source $CONFIG_FILE' or restart your terminal to apply."
        fi
    else
        echo "Could not automatically add $INSTALL_DIR to PATH. Please add it manually:"
        echo "export PATH=\"\$PATH:$INSTALL_DIR\""
    fi
fi

# Force first download
ANDROID_CLI_FRESH_INSTALL=1 "${INSTALL_DIR}/${BINARY_NAME}"

echo "----------------------------------------"
echo "✅ Success! $BINARY_NAME is ready to use."
echo "----------------------------------------"
