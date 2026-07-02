<p align="center">
  <img src="assets/icon.png" width="96" height="96" alt="eman-openagent icon">
</p>

# eman-openagent

Adds an **"Open Agent"** item to the Windows Explorer context menu.
Right-click on a folder (or on empty space inside it), and a **Windows
Terminal** window opens right there with a picker for every
command-line AI agent installed on your machine (Claude Code, Codex,
Copilot CLI, Gemini CLI, DeepSeek, Aider, etc.) — click one, use the
arrow keys + Enter, or just press its number.

The picker lists your **most-used agent first**, based on how often
you've picked each one before.

Detection happens live, on every click — it's not a static menu built
once. Install a new agent tomorrow and it just shows up in the list,
no reconfiguration needed.

## Requirements

- Windows 10/11
- PowerShell 5.1+ (already included with Windows)
- [Windows Terminal](https://aka.ms/terminal) installed (`wt.exe` on PATH)
- At least one command-line AI agent installed and on PATH
  (e.g. `claude`, `codex`, `copilot`, `gemini`, `aider`, `cursor-agent`)

No admin rights needed — the installer only touches
`HKEY_CURRENT_USER`, so it only affects your own Windows user account.

## Installation

### Quick install (no git required)

```powershell
irm https://raw.githubusercontent.com/Eman134/eman-openagent/main/install-remote.ps1 | iex
```

This downloads the project straight from GitHub as a zip, installs it
to `%LOCALAPPDATA%\Programs\eman-openagent`, and registers the context
menu — no git, no manual cloning. As with any `irm | iex` one-liner,
only run it if you trust the source (it's this public repo).

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

After installing, if "Open Agent" doesn't show up right away in the
context menu, restart Explorer
(`taskkill /f /im explorer.exe && start explorer.exe`) or log off/on.

## Usage

1. Right-click on a folder, **or** on empty space inside a folder
   that's open in Explorer.
2. Click **"Open Agent"**.
3. Windows Terminal opens in that folder with a picker (only agents
   installed on your PATH show up, most-used first). Pick one by
   clicking it, using arrow keys + Enter, or pressing its number.
4. The chosen agent starts right there, in that folder.

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

Save the file, and it's live — next time you click "Open Agent", it
gets picked up automatically (as long as `checkCommand` is on PATH).

## Uninstall

```powershell
cd eman-openagent
.\uninstall.ps1
```

This removes the context menu entries. Your config file at
`%LOCALAPPDATA%\eman-openagent\agents.json` is kept (delete it manually
if you want it gone too).

## How it works

- `install.ps1` creates two keys under `HKCU:\Software\Classes`:
  - `Directory\shell\OpenAgent` — right-click on top of a folder.
  - `Directory\Background\shell\OpenAgent` — right-click on empty space
    inside a folder.
- Each key launches `wt.exe -d "<folder>" powershell -NoExit -File
  scripts\Select-Agent.ps1 -Path "<folder>"`.
- `Select-Agent.ps1` reads `agents.json`, tests which ones are
  available on PATH via `Get-Command`, and sorts the hits by usage
  count (tracked in `%LOCALAPPDATA%\eman-openagent\usage.json`).
- It then renders the picker directly in that console — a small
  P/Invoke layer around the Win32 console API (`ReadConsoleInput`)
  handles both mouse clicks and keyboard input, so no extra window or
  GUI toolkit is involved. Once you pick an agent, its usage count is
  bumped and its `runCommand` runs right there.

## Troubleshooting

- **The item doesn't show up in the menu**: restart Explorer or
  log off/on. Windows caches context menu entries and can take a
  moment to refresh.
- **"No agent found"**: make sure the agent is installed and reachable
  by opening a new terminal window and running `where <command>`.
- **Execution policy error**: run
  `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` once in
  PowerShell.

## License

MIT — see [LICENSE](LICENSE).
