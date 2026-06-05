---
name: repair-codex-windows-plugins
description: Use when Windows Codex upgrades or restarts leave computer-use@openai-bundled or chrome@openai-bundled unavailable, openai-bundled mirror files reset under .codex\.tmp, Chrome cache lacks latest, native host paths are stale, or logs show missing-helper-path, native pipe startup failure, helper transport failure, or bundled plugins missing from codex plugin list.
---

# Repair Codex Windows Plugins

## Overview

Repair Windows Codex bundled plugin drift after Desktop or CLI upgrades/restarts. Treat this as a fragile environment repair: prove the current failure, rebuild the local `openai-bundled` mirror and plugin cache, persist the final mirror outside `.codex\.tmp`, then verify with CLI, sandbox, helper transport, and Desktop logs.

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

2. Run the bundled wrapper first; it owns the stable final state:
   - It uses `scripts\install-computer-use-local.ps1` from `codex-windows-fast-patch-skill` as a staging repair script.
   - The staging script may rebuild `$env:USERPROFILE\.codex\.tmp\bundled-marketplaces\openai-bundled`, but `.tmp` is not the durable final source.
   - The wrapper must sync the repaired mirror to `$env:USERPROFILE\.codex\bundled-marketplaces\openai-bundled` and set `[marketplaces.openai-bundled].source` to that persistent path.

3. If you must call the known repair script directly:
   - `scripts\install-computer-use-local.ps1` from `codex-windows-fast-patch-skill`.
   - Run it with `-VerifyOnly`, not hand-written config edits.
   - It should sync installed `openai-bundled` to `$env:USERPROFILE\.codex\.tmp\bundled-marketplaces\openai-bundled`, rebuild local `computer-use`, set `CODEX_ELECTRON_ENABLE_WINDOWS_COMPUTER_USE=1`, set `[features].computer_use = true`, set `[windows].sandbox = 'unelevated'`, and remove stale Chrome native-host entries.
   - After direct use, still run the bundled wrapper so the mirror is copied out of `.tmp` and Chrome `latest` is restored.

4. Reinstall Chrome from the repaired bundled marketplace:

```powershell
codex plugin add chrome@openai-bundled
```

Then ensure `C:\Users\LHF\.codex\plugins\cache\openai-bundled\chrome\latest` is a junction to the installed Chrome version directory. Current CLI installs Chrome into a versioned cache directory but may not create `latest`.

5. Recheck plugin status:

```powershell
codex plugin list | Select-String -Pattern 'computer-use@openai-bundled|chrome@openai-bundled'
```

Both must be `installed, enabled`.

The `Marketplace openai-bundled` path should be under `.codex\bundled-marketplaces\openai-bundled`, not `.codex\.tmp\bundled-marketplaces\openai-bundled`.

6. Verify sandbox syntax with the current CLI form:

```powershell
codex sandbox "C:\Windows\System32\cmd.exe" /c echo OK
```

Expect `OK`. Do not switch to `codex sandbox windows ...` unless the installed CLI help explicitly requires that subcommand.

7. Run strict verification through the wrapper:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\repair-codex-windows-plugins\scripts\repair-codex-bundled-plugins.ps1" -StrictVerifyOnly
```

Expect `helper transport ok`, `OK`, and `strict verification ok`. Do not use `install-computer-use-local.ps1 -StrictVerifyOnly` after switching to the persistent mirror; that older script semantically expects the `.tmp` staging path.

8. Confirm runtime signals:
   - Chrome: `agent.browsers.list()` should include `Chrome` with type `extension`.
   - Computer Use: Desktop logs should end with `computer-use native pipe startup ready`.
   - If the current thread was opened before repair, start a fresh Codex thread after restart; native pipe capabilities are fixed at session startup.

9. Tell the user to fully quit and reopen Codex Desktop after repair so the app reloads user environment variables and plugin paths.

## Common Failures

| Symptom | Likely Cause | Action |
| --- | --- | --- |
| `codex plugin list` omits `openai-bundled` | Missing `.agents\plugins\marketplace.json` in local mirror | Run wrapper or `install-computer-use-local.ps1 -VerifyOnly` |
| Works after repair but breaks after Codex restart | Final `[marketplaces.openai-bundled].source` points at `.codex\.tmp`, which Desktop/CLI may refresh or partially clear | Run the wrapper so it syncs to `.codex\bundled-marketplaces\openai-bundled` and updates `config.toml` |
| Chrome plugin installed but cannot run | Stale `chrome-native-hosts.json` entry points to old missing `browser-client.mjs` or `extension-host.exe` | Let repair script clean stale entries, then `codex plugin add chrome@openai-bundled` |
| Wrapper fails with missing `chrome\latest\scripts\browser-client.mjs` | CLI installed Chrome into a versioned cache directory but did not create `latest` | Create/repair `chrome\latest` junction to the installed version directory, then rerun wrapper |
| Desktop log says `missing-helper-path` | Computer Use helper paths cannot be resolved from plugin cache | Rebuild bundled mirror and local computer-use cache |
| Current thread says native pipe path unavailable | Thread started before Desktop repaired/injected native pipe | Restart Codex Desktop and open a fresh thread |
| `EBUSY` while syncing bundled marketplace | Chrome `extension-host.exe` is locking the mirror | Stop bundled `extension-host` processes under `.codex\plugins\cache\openai-bundled`, then rerun repair |
| Strict verify expects `computer-use\latest` but only version dir exists | CLI install changed cache shape | Recreate a junction from `latest` to the installed version directory |
| `install-computer-use-local.ps1 -StrictVerifyOnly` says semantic config validation failed after persistence | Old direct verifier expects `.codex\.tmp\bundled-marketplaces\openai-bundled` | Use wrapper `-StrictVerifyOnly`, which validates helper transport and persistent plugin state |

## Guardrails

- Do not edit `C:\Program Files\WindowsApps` in place.
- Do not hand-edit `config.toml` with a brittle PowerShell one-liner.
- Do not leave `[marketplaces.openai-bundled].source` pointing at `.codex\.tmp` as the final state when the user reports breakage after every restart.
- Do not declare success until `codex plugin list`, sandbox, helper transport, and relevant Desktop logs have been checked.
- If `Get-AppxPackage -Name OpenAI.Codex` returns empty, do not stop; verify by installed paths, running processes, and CLI output.
