/**
 * Cross-platform keep-alive for MOHO viewport polling.
 *
 * Moho runs plugin update callbacks as part of its UI refresh cycle. When
 * the user isn't interacting with Moho, that cycle can pause.
 *
 * On Windows: spawns a hidden PowerShell process that calls Win32
 * RedrawWindow on the MOHO window (~4 Hz).
 *
 * On macOS: when a request is pending, posts a targeted pair of Tab key
 * events to Moho. Tab toggles the workspace UI; sending it twice restores the
 * exact visible state while causing Moho to run script update callbacks. Moho
 * is activated only for that instant, then the previously focused app is
 * restored.
 */

import { spawn, ChildProcess } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

let keepAliveProcess: ChildProcess | null = null;
let keepAliveTimer: ReturnType<typeof setInterval> | null = null;
let scriptPath: string | null = null;

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

// A one-shot wake briefly activates Moho, toggles its workspace twice, and
// restores the app the user was in. Node launches it only while req_*.json
// files exist, including when several concurrent requests share one wake.
const APPLESCRIPT_WAKE = `
tell application "System Events"
  set previousProcess to first application process whose frontmost is true
  set previousName to name of previousProcess
  set frontmost of application process "Moho" to true
  key code 48
  key code 48
  if previousName is not "Moho" then
    set frontmost of application process previousName to true
  end if
end tell
`;

/**
 * Start the keep-alive process. Works on Windows and macOS.
 * No-op on unsupported platforms or if already running.
 */
export function startKeepAlive(ipcDir = path.join(os.tmpdir(), "moho-mcp")): void {
  if (keepAliveProcess || keepAliveTimer) {
    return;
  }

  const platform = os.platform();
  if (platform !== "win32" && platform !== "darwin") {
    return;
  }

  // Write the script to the IPC temp directory
  const dir = ipcDir;
  try {
    fs.mkdirSync(dir, { recursive: true });
  } catch {
    // already exists
  }

  if (platform === "win32") {
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

    keepAliveProcess.on("exit", (code, signal) => {
      if (code !== null && code !== 0) {
        process.stderr.write(
          `[moho-mcp] Keep-alive exited (code=${code}, signal=${signal ?? "none"})\n`,
        );
      }
      keepAliveProcess = null;
    });
  } else {
    // macOS
    scriptPath = path.join(dir, "wake-moho.applescript");
    fs.writeFileSync(scriptPath, APPLESCRIPT_WAKE, "utf-8");

    const wakeIfPending = () => {
      if (keepAliveProcess || !scriptPath) return;

      let pending = false;
      try {
        pending = fs.readdirSync(ipcDir).some((name) => /^req_\d+\.json$/.test(name));
      } catch {
        return;
      }
      if (!pending) return;

      const child = spawn("osascript", [scriptPath], {
        stdio: ["ignore", "ignore", "pipe"],
        detached: false,
      });
      keepAliveProcess = child;
      child.stderr?.on("data", (chunk: Buffer) => {
        process.stderr.write(String(chunk));
      });
      child.on("exit", (code, signal) => {
        if (code !== null && code !== 0) {
          process.stderr.write(
            `[moho-mcp] Moho wake exited (code=${code}, signal=${signal ?? "none"})\n`,
          );
        }
        if (keepAliveProcess === child) keepAliveProcess = null;
      });
    };

    keepAliveTimer = setInterval(wakeIfPending, 100);
    wakeIfPending();
  }

  process.stderr.write("[moho-mcp] Keep-alive started (MOHO viewport refresh)\n");
}

/**
 * Stop the keep-alive process and clean up the temp script.
 */
export function stopKeepAlive(): void {
  if (keepAliveTimer) {
    clearInterval(keepAliveTimer);
    keepAliveTimer = null;
  }

  const wasRunning = Boolean(keepAliveProcess || scriptPath);
  if (keepAliveProcess) {
    keepAliveProcess.kill();
    keepAliveProcess = null;
  }

  if (scriptPath) {
    try {
      fs.unlinkSync(scriptPath);
    } catch {
      // ignore cleanup errors
    }
    scriptPath = null;
  }

  if (wasRunning) {
    process.stderr.write("[moho-mcp] Keep-alive stopped\n");
  }
}
