#!/bin/bash
echo "============================================"
echo " MohoMCP Plugin Installer (macOS)"
echo "============================================"
echo ""

set -e

# Where to install. Preference order:
#   1. MOHO_SCRIPTS env var (path to a ".../Scripts" folder)
#   2. Moho Pro's custom content folder (EditableFilesDir in user settings)
#   3. Scripts folder inside /Applications/Moho.app (macOS may block writes here)
SETTINGS="$HOME/Library/Preferences/Lost Marble/Moho Pro/14/Moho Pro14.user.settings"
if [ -z "$MOHO_SCRIPTS" ] && [ -f "$SETTINGS" ]; then
    CONTENT_DIR="$(grep -a '^"EditableFilesDir"' "$SETTINGS" | sed -E 's/^"EditableFilesDir"[[:space:]]+"(.*)"$/\1/')"
    if [ -n "$CONTENT_DIR" ] && [ -d "$CONTENT_DIR/Scripts" ]; then
        MOHO_SCRIPTS="$CONTENT_DIR/Scripts"
    fi
fi
SCRIPTS="${MOHO_SCRIPTS:-/Applications/Moho.app/Contents/Resources/Support/Scripts}"
DEST="$SCRIPTS/Menu/MohoMCP"
TOOL_DEST="$SCRIPTS/Tool"
SRC="$(cd "$(dirname "$0")" && pwd)/moho-plugin"

if [ ! -d "$SCRIPTS/Menu" ] || [ ! -f "$TOOL_DEST/_tool_list.txt" ]; then
    echo "ERROR: Moho scripts folder not found at $SCRIPTS"
    echo "Set MOHO_SCRIPTS to your Moho Scripts folder, e.g.:"
    echo "  MOHO_SCRIPTS=\"\$HOME/Documents/Moho Pro/Scripts\" ./install-plugin.sh"
    exit 1
fi
echo "Installing into: $SCRIPTS"
echo ""

echo "Creating directories..."
mkdir -p "$DEST/moho_mcp/tools"

echo "Copying main script and JSON library..."
cp -f "$SRC/MohoMCP_Server.lua" "$DEST/MohoMCP_Server.lua"
cp -f "$SRC/MohoMCP_RunJobs.lua" "$DEST/MohoMCP_RunJobs.lua"
cp -f "$SRC/json.lua" "$DEST/json.lua"

echo "Copying core modules..."
cp -f "$SRC/moho_mcp/server.lua" "$DEST/moho_mcp/server.lua"
cp -f "$SRC/moho_mcp/protocol.lua" "$DEST/moho_mcp/protocol.lua"
cp -f "$SRC/moho_mcp/validator.lua" "$DEST/moho_mcp/validator.lua"

echo "Copying tool handlers..."
cp -f "$SRC/moho_mcp/tools/document.lua" "$DEST/moho_mcp/tools/document.lua"
cp -f "$SRC/moho_mcp/tools/layer.lua" "$DEST/moho_mcp/tools/layer.lua"
cp -f "$SRC/moho_mcp/tools/bone.lua" "$DEST/moho_mcp/tools/bone.lua"
cp -f "$SRC/moho_mcp/tools/animation.lua" "$DEST/moho_mcp/tools/animation.lua"
cp -f "$SRC/moho_mcp/tools/mesh.lua" "$DEST/moho_mcp/tools/mesh.lua"
cp -f "$SRC/moho_mcp/tools/script.lua" "$DEST/moho_mcp/tools/script.lua"
cp -f "$SRC/moho_mcp/tools/batch.lua" "$DEST/moho_mcp/tools/batch.lua"

echo ""
echo "Copying MohoMCP Poller tool script..."
cp -f "$SRC/MohoMCP_Poller.lua" "$TOOL_DEST/MohoMCP_Poller.lua"

echo "Registering tool in tool list..."
if ! grep -q "MohoMCP_Poller" "$TOOL_DEST/_tool_list.txt" 2>/dev/null; then
    echo "tool	MohoMCP_Poller	..." >> "$TOOL_DEST/_tool_list.txt"
    echo "  Added MohoMCP_Poller to _tool_list.txt"
else
    echo "  MohoMCP_Poller already in _tool_list.txt"
fi

echo ""
echo "Verifying installation..."
find "$DEST" -type f
echo ""
ls -la "$TOOL_DEST/MohoMCP_Poller.lua"

echo ""
echo "============================================"
echo " Installation complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Open MOHO 14"
echo "  2. Scripts menu > MohoMCP > Start/Stop MohoMCP Server"
echo "  3. Select the 'MohoMCP Poller' tool from the toolbar"
echo "     (it will be in the last tool group)"
echo "  4. While the tool is selected, the server polls for requests"
echo ""
echo "Note: On macOS you may need to grant Accessibility permissions"
echo "      to Moho for input simulation (System Settings > Privacy"
echo "      & Security > Accessibility)."
