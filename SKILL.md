---
name: repair-codex-windows-plugins
description: Use when Windows Codex upgrades leave computer-use@openai-bundled or chrome@openai-bundled unavailable, openai-bundled marketplace/mirror files are missing, Chrome native host paths are stale, or Desktop logs show missing-helper-path, native pipe startup failure, helper transport failure, or codex plugin list omits bundled plugins.
---

# Repair Codex Windows Plugins

## Overview

Repair Windows Codex bundled plugin drift after Desktop or CLI upgrades. Treat this as a fragile environment repair: prove the current failure, repair the local `openai-bundled` mirror and plugin cache, then verify with CLI, sandbox, helper transport, and Desktop logs.

## Quick Command

Run the bundled wrapper first:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\repair-codex-windows-plugins\scripts\repair-codex-bundled-plugins.ps1"
```

For no-change validation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\repair-codex-windows-plugins\scripts\repair-codex-bundled-plugins.ps1" -StrictVerifyOnly
```

## Workflow

1. Inspect before changing anything:
   - `codex --version`
   - `codex plugin list`
   - `Get-Content "$env:USERPROFILE\.codex\config.toml"`
   - `Get-Content "$env:USERPROFILE\.codex\chrome-native-hosts.json"`
   - Check Desktop logs for `missing-helper-path`, `native pipe startup failed`, stale Chrome paths, or `EBUSY` in bundled marketplace sync.

2. Prefer the known repair script if present:
   - `scripts\install-computer-use-local.ps1` from `codex-windows-fast-patch-skill`.
   - Run it with `-VerifyOnly`, not hand-written config edits.
   - It should sync installed `openai-bundled` to `$env:USERPROFILE\.codex\.tmp\bundled-marketplaces\openai-bundled`, rebuild local `computer-use`, set `CODEX_ELECTRON_ENABLE_WINDOWS_COMPUTER_USE=1`, set `[features].computer_use = true`, set `[windows].sandbox = 'unelevated'`, and remove stale Chrome native-host entries.

3. Reinstall Chrome from the repaired bundled marketplace:

```powershell
codex plugin add chrome@openai-bundled
```

4. Recheck plugin status:

```powershell
codex plugin list | Select-String -Pattern 'computer-use@openai-bundled|chrome@openai-bundled'
```

Both must be `installed, enabled`.

5. Verify sandbox syntax with the current CLI form:

```powershell
codex sandbox "C:\Windows\System32\cmd.exe" /c echo OK
```

Expect `OK`. Do not switch to `codex sandbox windows ...` unless the installed CLI help explicitly requires that subcommand.

6. Run strict helper verification:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<path-to>\install-computer-use-local.ps1" -StrictVerifyOnly
```

Expect `helper transport ok` and `verification ok`.

7. Confirm runtime signals:
   - Chrome: `agent.browsers.list()` should include `Chrome` with type `extension`.
   - Computer Use: Desktop logs should end with `computer-use native pipe startup ready`.
   - If the current thread was opened before repair, start a fresh Codex thread after restart; native pipe capabilities are fixed at session startup.

8. Tell the user to fully quit and reopen Codex Desktop after repair so the app reloads user environment variables and plugin paths.

## Common Failures

| Symptom | Likely Cause | Action |
| --- | --- | --- |
| `codex plugin list` omits `openai-bundled` | Missing `.agents\plugins\marketplace.json` in local mirror | Run wrapper or `install-computer-use-local.ps1 -VerifyOnly` |
| Chrome plugin installed but cannot run | Stale `chrome-native-hosts.json` entry points to old missing `browser-client.mjs` or `extension-host.exe` | Let repair script clean stale entries, then `codex plugin add chrome@openai-bundled` |
| Desktop log says `missing-helper-path` | Computer Use helper paths cannot be resolved from plugin cache | Rebuild bundled mirror and local computer-use cache |
| Current thread says native pipe path unavailable | Thread started before Desktop repaired/injected native pipe | Restart Codex Desktop and open a fresh thread |
| `EBUSY` while syncing bundled marketplace | Chrome `extension-host.exe` is locking the mirror | Stop bundled `extension-host` processes under `.codex\plugins\cache\openai-bundled`, then rerun repair |
| Strict verify expects `computer-use\latest` but only version dir exists | CLI install changed cache shape | Recreate a junction from `latest` to the installed version directory |

## Guardrails

- Do not edit `C:\Program Files\WindowsApps` in place.
- Do not hand-edit `config.toml` with a brittle PowerShell one-liner.
- Do not declare success until `codex plugin list`, sandbox, helper transport, and relevant Desktop logs have been checked.
- If `Get-AppxPackage -Name OpenAI.Codex` returns empty, do not stop; verify by installed paths, running processes, and CLI output.
