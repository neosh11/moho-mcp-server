# moho-mcp-server

An MCP server for Moho Pro 14. It can inspect and edit documents, animate
layers and bones, render frames, control the Moho UI, and build a complete
layered cutout rig from transparent image parts.

The Node bridge is a bundled executable that MCP clients can launch with
`npx`. The application-side Lua plugin installs into Moho's **Custom Content**
folder, so it never modifies the signed application bundle or requires
administrator access.

This project is adapted from [Kveto/MohoMCP](https://github.com/Kveto/MohoMCP).
See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for attribution.

## Requirements

- Moho Pro 14 (14.4 recommended)
- Node.js 20 or newer
- macOS or Windows 10/11

On macOS, grant Accessibility permission to the application that launches the
MCP server. This lets the request wake-up helper and optional input tools
interact with Moho. `cliclick` is optional for mouse input:

```bash
brew install cliclick
```

## Install the Moho plugin

```bash
git clone https://github.com/neosh11/moho-mcp-server.git
cd moho-mcp-server
chmod +x install-plugin.sh
./install-plugin.sh
```

The macOS installer reads Moho's configured `EditableFilesDir` and currently
installs to paths such as `~/Documents/moho/Moho Pro/Scripts`. It supports both
`/Applications/Moho.app` and versioned app names because it does not write into
either bundle.

On Windows, run `install-plugin.bat` normally—administrator access is not
needed. If the Custom Content folder cannot be detected, pass it explicitly:

```cmd
install-plugin.bat "C:\Users\you\Documents\Moho\Moho Pro"
```

Restart Moho after the first install. Then choose
**Scripts > MohoMCP > Start/Stop MohoMCP Server**. There is no poller tool to
select.

See [docs/installation.md](docs/installation.md) for manual installation and
troubleshooting.

## Configure an MCP client

Use the prebuilt package from the latest GitHub release:

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

To pin this release, replace `latest/download` with
`download/v0.2.0/moho-mcp-server-0.2.0.tgz`.

All MCP protocol messages use stdout; operational logs use stderr.

## Tools

The server exposes 27 tools:

| Area | Tools |
| --- | --- |
| Document | `document_getInfo`, `document_getLayers`, `document_setFrame`, `document_screenshot` |
| Layers | `layer_getProperties`, `layer_getChildren`, `layer_getBones`, `layer_setTransform`, `layer_setVisibility`, `layer_setOpacity`, `layer_setName`, `layer_selectLayer` |
| Bones | `bone_getProperties`, `bone_setTransform`, `bone_selectBone` |
| Animation | `animation_getKeyframes`, `animation_getFrameState`, `animation_setKeyframe`, `animation_deleteKeyframe`, `animation_setInterpolation` |
| Mesh | `mesh_getPoints`, `mesh_getShapes` |
| Input | `input_mouseClick`, `input_mouseDrag`, `input_sendKeys` |
| Rigging | `rig_createCutout` |
| Batch | `batch_execute` |

`rig_createCutout` creates an ordered skeleton, transparent image layers, and
layer-to-bone bindings in one undoable operation. Image paths are supplied by
the caller and are not stored in this repository.

Use `batch_execute` whenever two or more operations can share one IPC round
trip. See [docs/tool-reference.md](docs/tool-reference.md) for schemas.

## Architecture

```text
MCP client <--stdio--> Node bridge <--JSON files--> Moho 14.4 Lua plugin
                                      /tmp/moho-mcp (macOS)
                                      %TEMP%\moho-mcp (Windows)
```

Request IDs reuse 100 bounded file slots, so polling remains fast and reliable
after an unlimited number of calls. On macOS the bridge wakes Moho only while a
request is pending, briefly restoring the previous foreground application
afterward. The plugin uses Moho 14's `ScriptInterfaceHelper` to obtain a valid
current document interface inside update callbacks.

## Development loop

```bash
npm install
npm run dev:install   # copy Lua files into Custom Content
npm run dev           # rebuild the Node bundle on TypeScript changes
```

For runtime Lua changes, stop the server in Moho, run `npm run dev:install`,
then start it again. Runtime modules are deliberately unloaded on Stop, so no
Moho restart is needed. Restart only after changing the menu entry itself.

Useful checks:

```bash
npm run dev:verify    # TypeScript, Vitest, Lua tests, lint, bundle
```

## License

Apache-2.0. Portions adapted from MohoMCP remain subject to its MIT notice; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
