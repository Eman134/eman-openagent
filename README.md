<p align="center">
  <img src="assets/icon.png" width="96" height="96" alt="eman-openagent icon">
</p>

# eman-openagent

Adds an **"Open Agent"** item to the Windows Explorer context menu: a
one-click launch of your most-used command-line AI agent, right there
in the folder you right-clicked. If more than one agent is installed,
a second item, **"Choose Agent..."**, also shows up — it opens a
**Windows Terminal** picker listing every agent detected on your
machine (Claude Code, Codex, Copilot CLI, Gemini CLI, DeepSeek, Aider,
etc.). Click one, use arrow keys + Enter, or press its number.

With only one agent installed, "Choose Agent..." is skipped entirely —
there'd be nothing to choose from. Every pick updates the usage count
behind "Open Agent", so it always points at whichever agent you
actually reach for most.

Detection happens live — it's not a static menu built once. Install a
new agent tomorrow and it just shows up in the picker, no
reconfiguration needed.

## Requirements

- Windows 10 (version 1903+) or Windows 11 — earlier versions can't
  install Windows Terminal at all
- Windows PowerShell 5.1 (built into Windows 10/11; PowerShell 7/pwsh
  is not required, the scripts always run under `powershell.exe`)
- [Windows Terminal](https://aka.ms/terminal) installed (`wt.exe` on PATH)
- At least one command-line AI agent installed and on PATH
  (e.g. `claude`, `codex`, `copilot`, `gemini`, `aider`, `cursor-agent`)

No admin rights needed — the installer only touches
`HKEY_CURRENT_USER`, so it only affects your own Windows user account.

On **Windows 11**, the default right-click menu is trimmed down and
puts classic entries like ours under **"Show more options"** (or
Shift+F10) — that's a Windows 11 platform behavior affecting every
classic context-menu tool, not something specific to this project.

## Installation

### Quick install

```powershell
irm https://raw.githubusercontent.com/Eman134/eman-openagent/main/install-remote.ps1 | iex
```

Downloads the project as a zip straight from GitHub, installs it to
`%LOCALAPPDATA%\Programs\eman-openagent`, and registers the context
menu. As with any `irm | iex` one-liner, only run it if you trust the
source (it's this public repo).

### From a git clone

```powershell
git clone https://github.com/Eman134/eman-openagent.git
cd eman-openagent
.\install.ps1
```

If PowerShell blocks script execution, run this once:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

After installing, if the menu items don't show up right away, restart
Explorer (`taskkill /f /im explorer.exe && start explorer.exe`) or log
off/on.

### Let your AI agent install it for you

If you're already talking to an AI coding agent (Claude Code, Codex,
Copilot, etc.), you can just hand it this:

```
Install eman-openagent from https://github.com/Eman134/eman-openagent —
either clone the repo and run install.ps1 with PowerShell, or run the
remote installer (irm .../install-remote.ps1 | iex, see the repo's
README for the exact URL). Confirm the "Open Agent" and "Choose
Agent..." items were registered in the Windows Explorer context menu.
```

## Usage

1. Right-click on a folder, **or** on empty space inside a folder
   that's open in Explorer.
2. Click **"Open Agent"** to launch your most-used agent immediately,
   or **"Choose Agent..."** to pick from the full list.
3. If you chose from the list, Windows Terminal opens in that folder
   with a picker (only agents installed on your PATH show up,
   most-used first) — click one, use arrow keys + Enter, or press its
   number.
4. The chosen agent starts right there, in that folder.

> **Just installed a new agent?** The menu only re-checks what's
> installed when you actually use it. Click **"Open Agent"** once (even
> if it launches your usual agent) to refresh things — if you now have
> 2+ agents detected, "Choose Agent..." will show up from then on. No
> need to reinstall or restart Explorer for this.

## Supported agents / adding your own

The agent list lives at:

```
%LOCALAPPDATA%\eman-openagent\agents.json
```

That file is automatically copied from the repo on first install, and
is yours to edit — changes won't affect the repository and won't be
overwritten on reinstall.

Each entry looks like this:

```json
{
  "name": "Name shown in the menu",
  "checkCommand": "command used to detect if it's installed",
  "runCommand": "command that will run in the terminal"
}
```

Bundled by default:

| Name                 | Detected command  |
|-----------------------|-------------------|
| Claude Code            | `claude`          |
| OpenAI Codex CLI       | `codex`           |
| GitHub Copilot CLI     | `copilot`         |
| Gemini CLI             | `gemini`          |
| Aider                  | `aider`           |
| Cursor Agent CLI       | `cursor-agent`    |
| DeepSeek CLI           | `deepseek`        |
| Amazon Q Developer CLI | `q`               |
| Qwen Code CLI          | `qwen`            |
| Goose                  | `goose`           |
| OpenCode               | `opencode`        |

Command names for some of these move fast and vary by install method —
if detection doesn't pick up an agent you have installed, just fix the
`checkCommand`/`runCommand` in your local `agents.json`.

To add another agent, just append a new object to the list, e.g.:

```json
{
  "name": "My Custom Agent",
  "checkCommand": "my-agent",
  "runCommand": "my-agent --some-flag"
}
```

Save the file, and it's live — next time you open the picker, it gets
picked up automatically (as long as `checkCommand` is on PATH).

## Uninstall

If you installed from a git clone:

```powershell
cd eman-openagent
.\uninstall.ps1
```

If you installed with the quick install (no local clone to run
`uninstall.ps1` from):

```powershell
irm https://raw.githubusercontent.com/Eman134/eman-openagent/main/uninstall-remote.ps1 | iex
```

Either way, this removes the context menu entries. Your config file at
`%LOCALAPPDATA%\eman-openagent\agents.json` (and usage stats) are kept;
delete that folder manually if you want them gone too. The remote
uninstaller additionally deletes the installed copy at
`%LOCALAPPDATA%\Programs\eman-openagent`.

## How it works

- `install.ps1` always registers `OpenAgentQuick` ("Open Agent") under
  `HKCU:\Software\Classes` at both `Directory\shell` (right-click on a
  folder) and `Directory\Background\shell` (right-click on empty space
  inside one). It launches `scripts\Run-Agent.ps1`.
- `Select-Agent.ps1` and `Run-Agent.ps1` share `scripts\Common.ps1`,
  which reads `agents.json`, tests which agents are available on PATH
  via `Get-Command`, and sorts the hits by usage count (tracked in
  `%LOCALAPPDATA%\eman-openagent\usage.json`).
- `Run-Agent.ps1` runs the top hit directly. `Select-Agent.ps1` (used
  by "Choose Agent...") opens in Windows Terminal and renders a picker
  straight in that console — a small P/Invoke layer around the Win32
  console API (`ReadConsoleInput`) handles both mouse clicks and
  keyboard input, so no extra window or GUI toolkit is involved.
- After any pick, `Common.ps1`'s `Sync-ContextMenu` runs: it bumps the
  usage count, refreshes "Open Agent"'s label to name the new top
  agent, and adds or removes the `OpenAgent` ("Choose Agent...") key
  depending on whether more than one agent is currently detected. Both
  items use `Position=Bottom`, which keeps them grouped together near
  Windows' own "Open in Terminal" entry.
- Since there's no background watcher, the menu only re-syncs when you
  actually use "Open Agent" or "Choose Agent...". If you install a
  second agent while only one was detected, "Choose Agent..." reappears
  the next time you click "Open Agent" (or immediately if you just
  re-run `install.ps1` / the remote installer).

## Troubleshooting

- **The items don't show up in the menu**: restart Explorer or
  log off/on. Windows caches context menu entries and can take a
  moment to refresh.
- **Installed a new agent, but "Choose Agent..." still isn't there**:
  click "Open Agent" once to trigger a re-sync (see the note under
  Usage above), or re-run `install.ps1` / the remote installer.
- **"No agent found"**: make sure the agent is installed and reachable
  by opening a new terminal window and running `where <command>`.
- **Execution policy error**: run
  `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` once in
  PowerShell.

## License

MIT — see [LICENSE](LICENSE).
