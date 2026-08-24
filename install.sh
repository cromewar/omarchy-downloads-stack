#!/bin/sh
# Downloads Stack — installer for the Omarchy bar plugin.
#
# Run from a clone:
#     ./install.sh
# Or straight from the internet:
#     curl -fsSL https://raw.githubusercontent.com/cromewar/omarchy-downloads-stack/main/install.sh | sh
set -eu

ID="cromewar.downloads-stack"
REPO="cromewar/omarchy-downloads-stack"
BRANCH="main"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$ID"

if ! command -v omarchy >/dev/null 2>&1; then
    echo "Error: 'omarchy' not found. This plugin needs Omarchy 4.x." >&2
    exit 1
fi

# Prefer the clone this script was run from; otherwise fetch the repo.
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || true)
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/manifest.json" ]; then
    SRC="$SELF_DIR"
else
    echo "Downloading Downloads Stack…"
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" | tar -xz -C "$TMP"
    SRC=$(find "$TMP" -maxdepth 2 -type f -name manifest.json -exec dirname {} \; | head -n 1)
fi

if [ -z "${SRC:-}" ] || [ ! -f "$SRC/manifest.json" ]; then
    echo "Error: could not locate the plugin source." >&2
    exit 1
fi

# Installing over a clone of itself would delete the files being copied.
if [ "$SRC" = "$DEST" ]; then
    echo "Already installed in place at $DEST."
else
    [ -d "$DEST" ] && echo "Upgrading Downloads Stack…" || echo "Installing Downloads Stack…"
    rm -rf "$DEST"
    mkdir -p "$(dirname "$DEST")"
    cp -r "$SRC" "$DEST"
    rm -rf "$DEST/.git"
fi

# `omarchy plugin enable` is an IPC call into the running shell, and the shell only
# knows about the plugins it found the last time it scanned. A plugin that was just
# copied into place is not in that list, so the call fails with "plugin '$ID' is not
# known" and the widget stays disabled -- which is why the icon never showed up.
if omarchy-shell shell ping >/dev/null 2>&1; then
    omarchy-shell -q shell rescanPlugins
else
    # Nothing is running to answer the IPC call; a fresh shell scans on startup.
    omarchy restart shell || true
fi

# rescanPlugins is fire-and-forget: it returns before the shell has registered the
# new plugin, so enabling has to be retried until the scan lands.
attempt=0
until omarchy plugin enable "$ID" >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 20 ]; then
        echo >&2
        echo "Error: the files are in $DEST, but enabling $ID failed:" >&2
        omarchy plugin enable "$ID" >&2 || true
        echo >&2
        echo "Finish by hand with:" >&2
        echo "    omarchy-shell shell rescanPlugins" >&2
        echo "    omarchy plugin enable $ID" >&2
        echo "    omarchy restart shell" >&2
        exit 1
    fi
    sleep 0.25
done

# Bar widgets do not reliably hot-reload; restart so the icon actually appears.
omarchy restart shell || true

echo
echo "Installed. The folder icon is now in your bar (right-hand section)."
echo "Move it with:  omarchy bar move $ID --section left"
