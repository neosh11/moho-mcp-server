#!/bin/bash
set -euo pipefail

echo "============================================"
echo " MohoMCP Plugin Installer (macOS)"
echo "============================================"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_ROOT="$SCRIPT_DIR/moho-plugin"
MENU_SRC="$PACKAGE_ROOT/Menu/MohoMCP"
MODULE_SRC="$PACKAGE_ROOT/Modules/MohoMCP"
MOHO_CONTENT_DIR="${MOHO_CONTENT_DIR:-}"

# Moho records its configured Custom Content folder as EditableFilesDir.
if [ -z "$MOHO_CONTENT_DIR" ]; then
    SETTINGS_ROOT="$HOME/Library/Preferences/Lost Marble/Moho Pro"
    for settings in "$SETTINGS_ROOT"/*/"Moho Pro"*.user.settings; do
        [ -f "$settings" ] || continue
        candidate="$(sed -n 's/^"EditableFilesDir"[[:space:]]*"\(.*\)"$/\1/p' "$settings" | head -n 1)"
        if [ -n "$candidate" ] && [ -d "$candidate" ]; then
            MOHO_CONTENT_DIR="$candidate"
        fi
    done
fi

# Fallbacks cover common defaults when settings have not been written yet.
if [ -z "$MOHO_CONTENT_DIR" ]; then
    for candidate in \
        "$HOME/Documents/Moho/Moho Pro" \
        "$HOME/Documents/moho/Moho Pro"
    do
        if [ -d "$candidate" ]; then
            MOHO_CONTENT_DIR="$candidate"
            break
        fi
    done
fi

if [ -z "$MOHO_CONTENT_DIR" ] || [ ! -d "$MOHO_CONTENT_DIR" ]; then
    echo "ERROR: Moho's Custom Content folder could not be found."
    echo ""
    echo "In Moho, choose File > Open Custom Content Folder to locate it, then run:"
    echo "  MOHO_CONTENT_DIR=\"/path/to/Moho Pro\" ./install-plugin.sh"
    exit 1
fi

SCRIPTS_DIR="$MOHO_CONTENT_DIR/Scripts"
DEST="$SCRIPTS_DIR/Menu/MohoMCP"
MODULE_DEST="$SCRIPTS_DIR/Modules/MohoMCP"

echo "Using Moho Custom Content: $MOHO_CONTENT_DIR"
echo "Installing menu entry to: $DEST"
echo "Installing runtime modules to: $MODULE_DEST"
echo ""

mkdir -p "$DEST" "$MODULE_DEST"
cp -R "$MENU_SRC/." "$DEST/"
cp -R "$MODULE_SRC/." "$MODULE_DEST/"

# Migrate the pre-0.2 layout, whose support files incorrectly lived under
# Menu/ and appeared as bogus commands in Moho's Scripts menu.
if [ -f "$DEST/json.lua" ]; then
    rm -f "$DEST/json.lua"
fi
if [ -d "$DEST/moho_mcp" ]; then
    rm -rf "$DEST/moho_mcp"
fi

# Remove the legacy selected-tool poller if an older release installed it.
LEGACY_POLLER="$SCRIPTS_DIR/Tool/MohoMCP_Poller.lua"
if [ -f "$LEGACY_POLLER" ]; then
    rm -f "$LEGACY_POLLER"
    echo "Removed obsolete MohoMCP Poller tool."
fi

TOOL_LIST="$SCRIPTS_DIR/Tool/_tool_list.txt"
if [ -f "$TOOL_LIST" ] && grep -q "MohoMCP_Poller" "$TOOL_LIST"; then
    CLEANED_TOOL_LIST="$(mktemp)"
    awk '!/MohoMCP_Poller/' "$TOOL_LIST" > "$CLEANED_TOOL_LIST"
    cp "$CLEANED_TOOL_LIST" "$TOOL_LIST"
    rm -f "$CLEANED_TOOL_LIST"
    echo "Removed obsolete poller registration from _tool_list.txt."
fi

echo ""
echo "Installed files:"
find "$DEST" "$MODULE_DEST" -type f | sort
echo ""
echo "============================================"
echo " Installation complete"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Restart Moho after the first install or a menu-entry change"
echo "  2. Choose Scripts > MohoMCP > Start/Stop MohoMCP Server"
echo "  3. For runtime Lua edits: stop, run this installer, then start again"
echo "  4. Start the MCP client; no polling tool is required"
