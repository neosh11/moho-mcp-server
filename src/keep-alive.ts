/**
 * Cross-platform keep-alive for MOHO viewport polling.
 *
 * MOHO's Lua polling relies on DrawMe callbacks that only fire during
 * viewport repaints.  When the user isn't interacting with MOHO the
 * viewport stops repainting and polling stalls.
 *
 * On Windows: spawns a hidden PowerShell process that calls Win32
 * RedrawWindow on the MOHO window (~4 Hz).
 *
 * On macOS: Moho does not repaint while it is in the background, so there is
 * nothing to redraw from outside.  Instead a tiny stay-open applet
 * ("MohoMCP KeepAlive") reads Moho's Scripts > MohoMCP menu through the
 * Accessibility API ~4 times a second.  Reading the menu makes Moho call the
 * menu script's IsEnabled(), which polls for requests — without bringing
 * Moho to the front.  Renders, which crash Moho when run inside a poll, are
 * parked by the plugin and run when the applet presses Scripts > MohoMCP >
 * Run MohoMCP Jobs.  The applet lives at a stable path so the one-time
 * Accessibility / Automation grant survives updates of the bridge, is launched
 * through LaunchServices (so macOS attributes the permission to the applet
 * itself, not to whatever started the bridge) and quits on its own once no
 * moho-mcp-server process is left.
 */

import { spawn, spawnSync, ChildProcess } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

let keepAliveProcess: ChildProcess | null = null;
let scriptPath: string | null = null;
let macKeepAliveStarted = false;

// PowerShell script that forces MOHO viewport repaints via Win32 API.
const PS_SCRIPT = `
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public class MohoKeepAlive {
    [DllImport("user32.dll")]
    public static extern bool RedrawWindow(IntPtr hWnd, IntPtr lprcUpdate, IntPtr hrgnUpdate, uint flags);

    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr hWndParent, EnumChildProc lpEnumFunc, IntPtr lParam);

    public delegate bool EnumChildProc(IntPtr hWnd, IntPtr lParam);

    private static List<IntPtr> childWindows = new List<IntPtr>();

    private static bool EnumCallback(IntPtr hWnd, IntPtr lParam) {
        childWindows.Add(hWnd);
        return true;
    }

    public static IntPtr[] GetChildWindows(IntPtr parent) {
        childWindows.Clear();
        EnumChildWindows(parent, EnumCallback, IntPtr.Zero);
        return childWindows.ToArray();
    }
}
"@

$WM_MOUSEMOVE = 0x0200
$RDW_INVALIDATE = 0x0001
$RDW_UPDATENOW  = 0x0100
$RDW_ALLCHILDREN = 0x0080
$rdwFlags = $RDW_INVALIDATE -bor $RDW_UPDATENOW -bor $RDW_ALLCHILDREN

while ($true) {
    $procs = Get-Process -Name "Moho*" -ErrorAction SilentlyContinue
    if (-not $procs) {
        Start-Sleep -Seconds 2
        continue
    }
    foreach ($p in $procs) {
        $hwnd = $p.MainWindowHandle
        if ($hwnd -ne [IntPtr]::Zero) {
            [MohoKeepAlive]::RedrawWindow($hwnd, [IntPtr]::Zero, [IntPtr]::Zero, $rdwFlags) | Out-Null
            $children = [MohoKeepAlive]::GetChildWindows($hwnd)
            foreach ($child in $children) {
                [MohoKeepAlive]::PostMessage($child, $WM_MOUSEMOVE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
            }
        }
    }
    Start-Sleep -Milliseconds 250
}
`;

// The macOS keep-alive is split in two so that changing its logic never
// invalidates the user's permission grants:
//  - the applet ("MohoMCP KeepAlive.app") is a tiny stay-open loader. macOS
//    ties Accessibility/Automation grants to its code signature, so it is
//    rebuilt only when MAC_APPLET_VERSION changes;
//  - the worker (keepalive-worker.scpt next to it) holds the logic. The
//    applet loads it at launch, so a new worker only needs an applet restart.
const MAC_APPLET_VERSION = "2";
const MAC_WORKER_VERSION = "1";
const MAC_APPLET_ID = "dev.moho-mcp.keepalive";

const MAC_APPLET_SOURCE = String.raw`
property worker : missing value

on run
	set worker to load script (POSIX file "@@WORKER@@")
	worker's init()
end run

on idle
	try
		set r to worker's tick()
	on error
		return 2
	end try
	if r < 0 then
		quit
		return 1
	end if
	return r
end idle
`;

// Called by the applet ~4 times a second. Reading Moho's Scripts > MohoMCP
// menu makes Moho call the menu script's IsEnabled(), which polls for
// requests. When the plugin parks a request that must not run inside a poll
// (a render), it creates <ipcDir>/jobs.pending and the worker presses
// Scripts > MohoMCP > Run MohoMCP Jobs instead. State goes to
// <ipcDir>/keepalive.json so the bridge and the plugin can see it.
const MAC_WORKER_SOURCE = String.raw`
property idleTicks : 0
property lastState : ""
property ipcDir : ""

on init()
	set ipcDir to (do shell script "getconf DARWIN_USER_TEMP_DIR") & "moho-mcp/"
	set idleTicks to 0
	set lastState to ""
end init

on reportState(s)
	if s is not lastState then
		set lastState to s
		try
			do shell script "mkdir -p " & quoted form of ipcDir & "; printf '%s' " & quoted form of s & " > " & quoted form of (ipcDir & "keepalive.json")
		end try
	end if
end reportState

on tick()
	set idleTicks to idleTicks + 1
	if idleTicks mod 20 = 0 then
		try
			do shell script "pgrep -f moho-mcp-server >/dev/null"
		on error
			return -1
		end try
	end if
	try
		tell application "System Events"
			if not (exists process "Moho") then
				my reportState("{\"state\":\"moho-not-running\"}")
				return 2
			end if
			set jobsPending to exists file (ipcDir & "jobs.pending")
			tell process "Moho"
				set m to menu 1 of menu item "MohoMCP" of menu 1 of menu bar item "Scripts" of menu bar 1
				if jobsPending then
					try
						click menu item "Run MohoMCP Jobs" of m
					end try
				end if
				get name of menu items of m
			end tell
		end tell
		my reportState("{\"state\":\"ok\"}")
	on error errMsg number errNum
		my reportState("{\"state\":\"error\",\"code\":" & errNum & "}")
		return 2
	end try
	return 0.25
end tick
`;

function macSupportDir(): string {
  return path.join(os.homedir(), "Library", "Application Support", "moho-mcp");
}

function macAppletPath(): string {
  return path.join(macSupportDir(), "MohoMCP KeepAlive.app");
}

function macWorkerPath(): string {
  return path.join(macSupportDir(), "keepalive-worker.scpt");
}

function run(cmd: string, args: string[]): void {
  const r = spawnSync(cmd, args, { stdio: "ignore" });
  if (r.status !== 0) {
    throw new Error(`${cmd} ${args.join(" ")} exited with ${r.status}`);
  }
}

function stopMacApplet(): void {
  spawnSync("pkill", ["-f", "MohoMCP KeepAlive.app/Contents/MacOS/"], { stdio: "ignore" });
}

// Version markers live outside the bundle: writing inside it would break the
// signature and with it the grants.
function upToDate(marker: string, version: string): boolean {
  try {
    return fs.readFileSync(marker, "utf-8") === version;
  } catch {
    return false;
  }
}

function compileAppleScript(source: string, out: string, extraArgs: string[] = []): void {
  const src = path.join(os.tmpdir(), `moho-mcp-${process.pid}-${path.basename(out)}.applescript`);
  fs.writeFileSync(src, source, "utf-8");
  try {
    run("osacompile", [...extraArgs, "-o", out, src]);
  } finally {
    fs.rmSync(src, { force: true });
  }
}

/**
 * Build the worker and the applet if missing or out of date.
 * Returns the applet path and whether a running applet must be restarted.
 */
function ensureMacApplet(): { app: string; restart: boolean } {
  const app = macAppletPath();
  const worker = macWorkerPath();
  fs.mkdirSync(macSupportDir(), { recursive: true });
  let restart = false;

  const workerMarker = `${worker}.version`;
  if (!upToDate(workerMarker, MAC_WORKER_VERSION) || !fs.existsSync(worker)) {
    const tmp = `${worker}.new`;
    compileAppleScript(MAC_WORKER_SOURCE, tmp);
    fs.renameSync(tmp, worker);
    fs.writeFileSync(workerMarker, MAC_WORKER_VERSION, "utf-8");
    restart = true;
    process.stderr.write(`[moho-mcp] Built keep-alive worker at ${worker}\n`);
  }

  const appMarker = `${app}.version`;
  if (!upToDate(appMarker, MAC_APPLET_VERSION) || !fs.existsSync(app)) {
    stopMacApplet();
    fs.rmSync(app, { recursive: true, force: true });
    compileAppleScript(MAC_APPLET_SOURCE.replace("@@WORKER@@", worker), app, ["-s"]);
    const plist = path.join(app, "Contents", "Info.plist");
    run("plutil", ["-replace", "CFBundleIdentifier", "-string", MAC_APPLET_ID, plist]);
    run("plutil", ["-replace", "CFBundleName", "-string", "MohoMCP KeepAlive", plist]);
    run("plutil", ["-replace", "LSUIElement", "-bool", "true", plist]);
    run("plutil", [
      "-replace",
      "NSAppleEventsUsageDescription",
      "-string",
      "Reads the Moho menu so the MohoMCP plugin keeps answering requests while Moho is in the background.",
      plist,
    ]);
    // Info.plist changed after osacompile signed it — re-sign ad hoc.
    run("codesign", ["--force", "--sign", "-", app]);
    fs.writeFileSync(appMarker, MAC_APPLET_VERSION, "utf-8");
    restart = false; // nothing of the old applet is running any more
    process.stderr.write(
      `[moho-mcp] Built keep-alive applet at ${app}; grant it Accessibility access again\n`,
    );
  }
  return { app, restart };
}

function startMacKeepAlive(): void {
  let built: { app: string; restart: boolean };
  try {
    built = ensureMacApplet();
  } catch (err) {
    process.stderr.write(`[moho-mcp] Keep-alive applet build failed: ${String(err)}\n`);
    return;
  }
  if (built.restart) {
    // The applet loads the worker only at launch.
    stopMacApplet();
  }
  // `open` launches through LaunchServices: -g keeps it in the background,
  // -j hides it. Re-opening an already running applet is a no-op.
  const child = spawn("open", ["-g", "-j", built.app], { stdio: "ignore" });
  child.on("error", (err) => {
    process.stderr.write(`[moho-mcp] Keep-alive launch failed: ${String(err)}\n`);
  });
  macKeepAliveStarted = true;
  process.stderr.write("[moho-mcp] Keep-alive started (MohoMCP KeepAlive applet)\n");
}

/**
 * Hint for a timed-out request, based on what the macOS applet last reported.
 * Returns an empty string when there is nothing useful to add.
 */
export function keepAliveHint(ipcDir: string): string {
  if (os.platform() !== "darwin") {
    return "";
  }
  let state: { state?: string; code?: number } = {};
  try {
    state = JSON.parse(fs.readFileSync(path.join(ipcDir, "keepalive.json"), "utf-8"));
  } catch {
    return " The MohoMCP KeepAlive applet has not reported yet; if macOS asked for permission, allow it.";
  }
  if (state.state === "error") {
    if (state.code === -1719 || state.code === -25211) {
      return (
        " Give \"MohoMCP KeepAlive\" Accessibility access in System Settings > Privacy & Security > Accessibility " +
        `(app: ${macAppletPath()}).`
      );
    }
    if (state.code === -1743) {
      return " Allow \"MohoMCP KeepAlive\" to control System Events in System Settings > Privacy & Security > Automation.";
    }
    return (
      ` The keep-alive applet cannot read Moho's Scripts > MohoMCP menu (error ${state.code}); ` +
      "check that the MohoMCP plugin is installed and that no modal dialog is open in Moho."
    );
  }
  if (state.state === "ok") {
    return " Moho is reachable; start the server via Scripts > MohoMCP > Start/Stop MohoMCP Server and close any open dialog.";
  }
  return "";
}

/**
 * Start the keep-alive process. Works on Windows and macOS.
 * No-op on unsupported platforms or if already running.
 */
export function startKeepAlive(): void {
  // Never build or launch the real applet from the test suite.
  if (process.env.VITEST) {
    return;
  }
  const platform = os.platform();
  if (platform === "darwin") {
    if (!macKeepAliveStarted) {
      startMacKeepAlive();
    }
    return;
  }
  if (keepAliveProcess || platform !== "win32") {
    return;
  }

  // Write the script to the IPC temp directory
  const dir = path.join(os.tmpdir(), "moho-mcp");
  try {
    fs.mkdirSync(dir, { recursive: true });
  } catch {
    // already exists
  }

  scriptPath = path.join(dir, "keep-alive.ps1");
  fs.writeFileSync(scriptPath, PS_SCRIPT, "utf-8");

  keepAliveProcess = spawn(
    "powershell",
    ["-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", scriptPath],
    {
      stdio: "ignore",
      detached: false,
      windowsHide: true,
    },
  );

  keepAliveProcess.on("exit", () => {
    keepAliveProcess = null;
  });

  process.stderr.write("[moho-mcp] Keep-alive started (MOHO viewport refresh)\n");
}

/**
 * Stop the keep-alive process and clean up the temp script.
 */
export function stopKeepAlive(): void {
  // The macOS applet may be shared by several bridges (one per Claude
  // session); it quits by itself once no moho-mcp-server process is left.
  macKeepAliveStarted = false;

  if (keepAliveProcess) {
    keepAliveProcess.kill();
    keepAliveProcess = null;
    process.stderr.write("[moho-mcp] Keep-alive stopped\n");
  }

  if (scriptPath) {
    try {
      fs.unlinkSync(scriptPath);
    } catch {
      // ignore cleanup errors
    }
    scriptPath = null;
  }
}
