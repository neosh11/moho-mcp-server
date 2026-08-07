# Installation

## 1. Install the Lua plugin into Custom Content

Moho 14.4 loads user extensions from its configured **Custom Content** folder.
Installing there is upgrade-safe and avoids macOS code-signing and permission
errors caused by editing `/Applications/Moho.app`.

### macOS

```bash
chmod +x install-plugin.sh
./install-plugin.sh
```

The installer reads `EditableFilesDir` from Moho's user settings. Override it
when needed:

```bash
MOHO_CONTENT_DIR="$HOME/Documents/moho/Moho Pro" ./install-plugin.sh
```

### Windows

Run without administrator privileges:

```cmd
install-plugin.bat
```

Or pass the Custom Content folder:

```cmd
install-plugin.bat "C:\Users\you\Documents\Moho\Moho Pro"
```

### Installed layout

```text
<Custom Content>/Scripts/
├── Menu/MohoMCP/
│   └── MohoMCP_Server.lua
└── Modules/MohoMCP/
    ├── json.lua
    └── moho_mcp/
        ├── protocol.lua
        ├── server.lua
        ├── validator.lua
        └── tools/
```

Only the entrypoint lives under `Menu/`. Keeping runtime modules under
`Modules/` prevents Moho from displaying implementation files as bogus Scripts
menu commands.

For a manual install, copy the repository's `moho-plugin/Menu` and
`moho-plugin/Modules` folders into `<Custom Content>/Scripts`, preserving that
layout.

Restart Moho after the first install. Choose
**Scripts > MohoMCP > Start/Stop MohoMCP Server** and confirm that
`/tmp/moho-mcp/status.json` (macOS) or `%TEMP%\moho-mcp\status.json` (Windows)
appears.

## 2. Configure the MCP client

```json
{
  "mcpServers": {
    "moho-mcp": {
      "command": "npx",
      "args": [
        "-y",
        "https://github.com/neosh11/moho-mcp-server/releases/latest/download/moho-mcp-server.tgz"
      ]
    }
  }
}
```

For local development:

```bash
npm install
npm run build
```

```json
{
  "mcpServers": {
    "moho-mcp": {
      "command": "node",
      "args": ["/absolute/path/to/moho-mcp-server/dist/moho-mcp-server.mjs"]
    }
  }
}
```

## macOS permissions

Grant Accessibility access to the application that launches the MCP bridge
(for example Terminal, Codex, or another desktop client) under
**System Settings > Privacy & Security > Accessibility**. The bridge uses this
only when a request is pending and restores the previously focused application.

The optional input tools work best with `cliclick`:

```bash
brew install cliclick
```

## Development reload loop

Runtime modules reload without restarting Moho:

1. Choose **Scripts > MohoMCP > Start/Stop MohoMCP Server** to stop.
2. Run `npm run dev:install`.
3. Start the server again from the same menu item.

Restart Moho only after changing `MohoMCP_Server.lua`, because Moho owns the
menu entry lifecycle. Use `npm run dev:verify` for all automated checks.

## Troubleshooting

### `Operation not permitted` inside `/Applications/Moho.app`

An old installer is being used. Current releases install into Custom Content
and never require `sudo` or modify the app bundle.

### The Scripts menu contains `json`, `RT: ...`, or tool implementation names

Upgrade with the current platform installer. It removes the pre-0.2 runtime
files from `Scripts/Menu/MohoMCP` and places them under `Scripts/Modules`.
Restart Moho afterward.

### The bridge reports no `status.json`

- Start the server from **Scripts > MohoMCP**.
- On macOS check `ls /tmp/moho-mcp/status.json`.
- On Windows check `dir %TEMP%\moho-mcp\status.json`.
- Confirm Moho has an open document.

### Requests time out on macOS

- Grant Accessibility permission to the MCP-launching application.
- Keep the Moho window open (it may remain in the background).
- Inspect **Window > Lua Console** for `[MohoMCP]` errors.

### Full-window input or screenshots fail

- Keep Moho visible and not minimized.
- Capture `document_screenshot` with `mode: "full"` before coordinate input.
- Install `cliclick` when mouse input is unreliable.
