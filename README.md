# Repair Codex Windows Plugins

用于修复 Windows 上 Codex Desktop / CLI 升级或重启后 bundled 插件漂移的问题，重点覆盖 `computer-use@openai-bundled` 和 `chrome@openai-bundled`。

## 适用场景

- `computer-use@openai-bundled` 或 `chrome@openai-bundled` 无法加载
- 每次重启 Codex 后插件又不可用
- `codex plugin list` 找不到 `openai-bundled`
- `openai-bundled` mirror 缺少 `.agents\plugins\marketplace.json`
- Chrome cache 只有版本目录，缺少 `chrome\latest`
- Chrome native host 指向旧的 `browser-client.mjs` 或 `extension-host.exe`
- Desktop 日志出现 `missing-helper-path`、`native pipe startup failed` 或 `helper transport failure`

## 安装

安装到 Codex skill 目录：

```powershell
git clone https://github.com/3027726980/repair-codex-windows-plugins.git "$env:USERPROFILE\.codex\skills\repair-codex-windows-plugins"
```

Gitee 镜像：

```powershell
git clone https://gitee.com/LHF-gitee/repair-codex-windows-plugins.git "$env:USERPROFILE\.codex\skills\repair-codex-windows-plugins"
```

## 快速修复

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\repair-codex-windows-plugins\scripts\repair-codex-bundled-plugins.ps1"
```

只验证当前状态：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\repair-codex-windows-plugins\scripts\repair-codex-bundled-plugins.ps1" -StrictVerifyOnly
```

## 修复逻辑

wrapper 会先调用现有的 `install-computer-use-local.ps1` 作为 staging 修复器，重建临时 bundled marketplace 和 `computer-use` 本地兼容插件。

随后 wrapper 会把修复后的 `openai-bundled` mirror 同步到持久路径：

```text
C:\Users\<you>\.codex\bundled-marketplaces\openai-bundled
```

并将 `config.toml` 中的 `[marketplaces.openai-bundled].source` 指向这个持久路径。这样普通重启不再依赖 `.codex\.tmp\bundled-marketplaces\openai-bundled`，避免 `.tmp` 被刷新或残缺后导致插件再次消失。

wrapper 还会修复 Chrome 插件缓存形态：

```text
C:\Users\<you>\.codex\plugins\cache\openai-bundled\chrome\latest
```

`latest` 应该是指向当前 Chrome 插件版本目录的 Junction，并且里面必须存在：

- `scripts\browser-client.mjs`
- `extension-host\windows\x64\extension-host.exe`

## 验证标准

修复后应满足：

- `codex plugin list` 显示 `Marketplace openai-bundled`
- `openai-bundled` marketplace 路径在 `.codex\bundled-marketplaces\openai-bundled`
- `computer-use@openai-bundled` 为 `installed, enabled`
- `chrome@openai-bundled` 为 `installed, enabled`
- `codex sandbox "C:\Windows\System32\cmd.exe" /c echo OK` 返回 `OK`
- wrapper `-StrictVerifyOnly` 输出 `helper transport ok` 和 `strict verification ok`

修复完成后，完全退出并重新打开 Codex Desktop，让桌面端重新加载用户环境变量和插件路径。

## 常见问题

### 为什么重启后又坏了？

旧流程会把 `[marketplaces.openai-bundled].source` 指向 `.codex\.tmp\bundled-marketplaces\openai-bundled`。这个目录适合作为 staging mirror，但不适合作为长期来源，因为 Codex 重启、升级或 marketplace 同步时可能刷新它。

本 skill 的 wrapper 会把最终来源迁移到 `.codex\bundled-marketplaces\openai-bundled`，从而减少每次重启后重新修复的情况。

### 为什么不直接用 `install-computer-use-local.ps1 -StrictVerifyOnly`？

旧脚本的 strict verifier 语义上期待 `.tmp` staging 路径。持久化后请使用本 skill 的 wrapper：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\repair-codex-windows-plugins\scripts\repair-codex-bundled-plugins.ps1" -StrictVerifyOnly
```

### Chrome 报缺少 `latest` 怎么办？

运行 wrapper。当前 CLI 可能只安装 Chrome 到版本目录，例如 `chrome\26.x.xxxxx`，但没有创建 `chrome\latest`。wrapper 会补齐这个 Junction 并验证关键文件存在。

## English

This Codex skill repairs Windows Codex bundled plugin drift after Desktop or CLI upgrades/restarts, especially for `computer-use@openai-bundled` and `chrome@openai-bundled`.

It rebuilds the bundled marketplace mirror, moves the final `openai-bundled` source out of `.codex\.tmp` into a persistent mirror under `.codex\bundled-marketplaces\openai-bundled`, repairs plugin cache shape, restores Chrome `latest`, and verifies plugin status, sandbox, and Computer Use helper transport.

Quick repair:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\repair-codex-windows-plugins\scripts\repair-codex-bundled-plugins.ps1"
```

Verify only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\repair-codex-windows-plugins\scripts\repair-codex-bundled-plugins.ps1" -StrictVerifyOnly
```

After repair, fully quit and reopen Codex Desktop so it reloads user environment variables and plugin paths.
