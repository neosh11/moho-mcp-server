# moho-mcp-server

An MCP server for Moho Pro 14. It lets MCP clients inspect documents, edit
layers and animation, render frames, capture the Moho window, and send mouse
or keyboard input.

The bridge is distributed as a bundled npm executable, so MCP clients can run
it directly with `npx`. A Lua plugin inside Moho handles the application-side
operations through file-based JSON-RPC.

This project is adapted from
[Kveto/MohoMCP](https://github.com/Kveto/MohoMCP). See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for attribution.

## Requirements

- Moho Pro 14
- Node.js 20 or newer
- Windows 10/11 or macOS

On macOS, input simulation requires Accessibility permission for the app that
starts the MCP server. `cliclick` is optional but recommended for reliable
mouse input:

```bash
brew install cliclick
```

Moho only runs the plugin's poller while it redraws or updates its menus, and
in the background it does neither. On macOS the bridge therefore builds and
starts a small background applet, `~/Library/Application Support/moho-mcp/MohoMCP KeepAlive.app`,
which reads Moho's **Scripts > MohoMCP** menu about four times a second
without bringing Moho to the front. On first start allow it to control
System Events, and turn it on in **System Settings > Privacy & Security >
Accessibility**. The applet quits by itself once no bridge is running.

## Install the Moho plugin

Clone this repository, then run the installer for your platform:

```bash
git clone https://github.com/neosh11/moho-mcp-server.git
cd moho-mcp-server
chmod +x install-plugin.sh
./install-plugin.sh
```

On Windows, run `install-plugin.bat` as an administrator. The installer copies
the menu script, poller, JSON library, and tool handlers into the Moho 14
application scripts directories.

You can also install the files manually. See
[docs/installation.md](docs/installation.md).

## Configure an MCP client

Run the prebuilt package directly from the latest GitHub release:

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

For local development, build the bundle and point the client at it:

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

## Start MohoMCP

1. Open Moho Pro 14 and load a project.
2. Choose **Scripts > MohoMCP > Start/Stop MohoMCP Server**.
3. Select **MohoMCP Poller** from the toolbar.
4. Start or reconnect your MCP client.

The bridge starts automatically when the client launches:

```bash
npx -y https://github.com/neosh11/moho-mcp-server/releases/latest/download/moho-mcp-server.tgz
```

The `latest/download` URL follows the newest release. To pin a version, use
`https://github.com/neosh11/moho-mcp-server/releases/download/v0.1.0/moho-mcp-server-0.1.0.tgz`.
The tarball contains the prebuilt bundle and installs without transitive
dependencies.

All protocol messages use stdout. Status and error messages use stderr.

## Tools

The server exposes 26 tools:

| Area | Tools |
| --- | --- |
| Document | `document_getInfo`, `document_getLayers`, `document_setFrame`, `document_screenshot` |
| Layers | `layer_getProperties`, `layer_getChildren`, `layer_getBones`, `layer_setTransform`, `layer_setVisibility`, `layer_setOpacity`, `layer_setName`, `layer_selectLayer` |
| Bones | `bone_getProperties`, `bone_setTransform`, `bone_selectBone` |
| Animation | `animation_getKeyframes`, `animation_getFrameState`, `animation_setKeyframe`, `animation_deleteKeyframe`, `animation_setInterpolation` |
| Mesh | `mesh_getPoints`, `mesh_getShapes` |
| Input | `input_mouseClick`, `input_mouseDrag`, `input_sendKeys` |
| Batch | `batch_execute` |

It also exposes `moho://shortcuts` and `moho://tools` as MCP resources.
See [docs/tool-reference.md](docs/tool-reference.md) for schemas and examples.

Use `batch_execute` for two or more independent Moho operations. A batch uses
one IPC round trip instead of one round trip per operation.

## Configuration

| Environment variable | Default | Description |
| --- | --- | --- |
| `MOHO_MCP_IPC_DIR` | `<system temp>/moho-mcp` | File IPC directory used by the Node bridge |

The Moho plugin and bridge must use the same IPC directory.

## Architecture

```text
MCP client <--stdio--> Node bridge <--JSON files--> Moho Lua plugin
                                      system temp
```

For each operation, the bridge writes `req_<id>.json`, waits for the plugin to
write `resp_<id>.json`, then removes the response. A platform-specific
keep-alive process keeps the Lua poller running while Moho is idle: on Windows
it repaints the Moho window, on macOS the KeepAlive applet reads Moho's menu.

## Development

```bash
npm install
npm run typecheck
npm test
npm run lint
npm run build
```

The bundled executable is written to `dist/moho-mcp-server.mjs`.

## License

Apache-2.0. Portions adapted from MohoMCP remain subject to its MIT notice;
see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
