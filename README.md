# Repair Codex Windows Plugins

## 中文说明

这是一个用于 Windows 上 Codex Desktop / CLI 升级后快速修复 bundled 插件漂移问题的 Codex Skill。它主要处理以下问题：

- `computer-use@openai-bundled` 无法运行
- `chrome@openai-bundled` 无法运行
- `codex plugin list` 找不到 `openai-bundled`
- 本地 `openai-bundled` marketplace mirror 缺少 `.agents\plugins\marketplace.json`
- Chrome native host 记录指向旧版本路径
- Codex Desktop 日志出现 `missing-helper-path`、`native pipe startup failed`、`helper transport failure`

## 安装方式

将本仓库放到 Codex Skill 目录：

```powershell
git clone https://github.com/3027726980/repair-codex-windows-plugins.git "$env:USERPROFILE\.codex\skills\repair-codex-windows-plugins"
```

如果你更偏好 Gitee：

```powershell
git clone https://gitee.com/LHF-gitee/repair-codex-windows-plugins.git "$env:USERPROFILE\.codex\skills\repair-codex-windows-plugins"
```

## 快速修复

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\repair-codex-windows-plugins\scripts\repair-codex-bundled-plugins.ps1"
```

只验证、不修复：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\repair-codex-windows-plugins\scripts\repair-codex-bundled-plugins.ps1" -StrictVerifyOnly
```

## 修复内容

脚本会优先定位已有的 `install-computer-use-local.ps1`，并复用现有的 Windows Codex fast patch 修复流程。它会检查并修复：

- `openai-bundled` 本地 marketplace mirror
- `computer-use@openai-bundled` 插件缓存
- `chrome@openai-bundled` 插件缓存
- `CODEX_ELECTRON_ENABLE_WINDOWS_COMPUTER_USE=1`
- `[features].computer_use = true`
- `[windows].sandbox = 'unelevated'`
- stale Chrome native-host entries

## 验证标准

修复后应满足：

- `computer-use@openai-bundled` 为 `installed, enabled`
- `chrome@openai-bundled` 为 `installed, enabled`
- `codex sandbox "C:\Windows\System32\cmd.exe" /c echo OK` 返回 `OK`
- helper transport 输出 `verification ok`
- Codex Desktop 日志出现 `computer-use native pipe startup ready`

修复完成后，请完全退出并重新打开 Codex Desktop，让桌面端重新加载环境变量和插件路径。

## English

This repository contains a Codex Skill for repairing Windows Codex bundled plugin drift after Codex Desktop or CLI upgrades. It is intended for issues such as:

- `computer-use@openai-bundled` cannot run
- `chrome@openai-bundled` cannot run
- `codex plugin list` does not show `openai-bundled`
- the local `openai-bundled` marketplace mirror is missing `.agents\plugins\marketplace.json`
- Chrome native host entries point to stale plugin paths
- Codex Desktop logs show `missing-helper-path`, `native pipe startup failed`, or `helper transport failure`

## Installation

Clone this repository into your Codex skills directory:

```powershell
git clone https://github.com/3027726980/repair-codex-windows-plugins.git "$env:USERPROFILE\.codex\skills\repair-codex-windows-plugins"
```

Or use Gitee:

```powershell
git clone https://gitee.com/LHF-gitee/repair-codex-windows-plugins.git "$env:USERPROFILE\.codex\skills\repair-codex-windows-plugins"
```

## Quick Repair

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\repair-codex-windows-plugins\scripts\repair-codex-bundled-plugins.ps1"
```

Verify only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\repair-codex-windows-plugins\scripts\repair-codex-bundled-plugins.ps1" -StrictVerifyOnly
```

## What It Repairs

The wrapper script locates the existing `install-computer-use-local.ps1` repair script and reuses the Windows Codex fast patch workflow. It checks and repairs:

- the local `openai-bundled` marketplace mirror
- `computer-use@openai-bundled` plugin cache
- `chrome@openai-bundled` plugin cache
- `CODEX_ELECTRON_ENABLE_WINDOWS_COMPUTER_USE=1`
- `[features].computer_use = true`
- `[windows].sandbox = 'unelevated'`
- stale Chrome native-host entries

## Verification

After repair:

- `computer-use@openai-bundled` should be `installed, enabled`
- `chrome@openai-bundled` should be `installed, enabled`
- `codex sandbox "C:\Windows\System32\cmd.exe" /c echo OK` should return `OK`
- helper transport should print `verification ok`
- Codex Desktop logs should show `computer-use native pipe startup ready`

Fully quit and reopen Codex Desktop after the repair so the app reloads environment variables and plugin paths.
