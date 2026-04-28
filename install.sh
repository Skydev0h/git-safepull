#!/usr/bin/env bash
set -euo pipefail

DEST="${1:-${HOME}/.local/bin}"

mkdir -p "$DEST"
cp git-safepull "$DEST/git-safepull"
chmod +x "$DEST/git-safepull"

echo "installed to $DEST/git-safepull"

if echo "$PATH" | tr ':' '\n' | grep -qx "$DEST"; then
    echo "run: git safepull"
    exit 0
fi

echo ""
echo "$DEST is not in your PATH."

shell_name="$(basename "${SHELL:-/bin/bash}")"
case "$shell_name" in
    zsh)
        rc="$HOME/.zshrc"
        line="export PATH=\"$DEST:\$PATH\""
        ;;
    fish)
        rc="$HOME/.config/fish/config.fish"
        line="fish_add_path $DEST"
        ;;
    *)
        rc="$HOME/.bashrc"
        line="export PATH=\"$DEST:\$PATH\""
        ;;
esac

echo ""
read -rp "add to $rc? [Y/n] " answer
case "${answer:-y}" in
    [Yy]*)
        echo "" >> "$rc"
        echo "# git-safepull" >> "$rc"
        echo "$line" >> "$rc"
        echo "added to $rc"
        echo ""
        echo "run: source $rc"
        echo "then: git safepull"
        ;;
    *)
        echo ""
        echo "add this line manually to your shell rc file ($rc or similar):"
        echo "  $line"
        ;;
esac
