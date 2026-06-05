[CmdletBinding()]
param(
  [string]$CodexHome = (Join-Path $env:USERPROFILE '.codex'),
  [string]$PersistentMarketplaceRoot,
  [string]$RepairScript,
  [switch]$StrictVerifyOnly,
  [switch]$SkipChromeAdd,
  [switch]$SkipComputerUseAdd
)

$ErrorActionPreference = 'Stop'
$LogPrefix = '[repair-codex-windows-plugins]'

function Write-Step {
  param([string]$Message)
  Write-Host "$LogPrefix $Message"
}

function Invoke-CodexText {
  param([string[]]$Arguments)
  $output = & codex @Arguments 2>&1
  $exitCode = $LASTEXITCODE
  $text = ($output | Out-String).Trim()
  if ($text) {
    Write-Host $text
  }
  if ($exitCode -ne 0) {
    throw "codex $($Arguments -join ' ') failed with exit code $exitCode"
  }
  return $text
}

function Resolve-RepairScript {
  param([string]$ExplicitPath)

  if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
    if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Leaf)) {
      throw "repair script not found: $ExplicitPath"
    }
    return (Resolve-Path -LiteralPath $ExplicitPath).Path
  }

  $candidates = @(
    (Join-Path $env:USERPROFILE '.codex\skills\codex-windows-fast-patch\scripts\install-computer-use-local.ps1'),
    (Join-Path $env:USERPROFILE 'Documents\Codex\2026-05-07\new-chat\codex-windows-fast-patch-skill\scripts\install-computer-use-local.ps1')
  )

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  foreach ($root in @((Join-Path $env:USERPROFILE 'Documents\Codex'), (Join-Path $env:USERPROFILE '.codex\skills'))) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
      continue
    }
    $found = Get-ChildItem -Path $root -Recurse -Filter 'install-computer-use-local.ps1' -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if ($found) {
      return $found.FullName
    }
  }

  return $null
}

function Ensure-ComputerUseLatestJunction {
  param([string]$CodexHomePath)

  $cacheRoot = Join-Path $CodexHomePath 'plugins\cache\openai-bundled\computer-use'
  if (-not (Test-Path -LiteralPath $cacheRoot -PathType Container)) {
    return
  }

  $latest = Join-Path $cacheRoot 'latest'
  if (Test-Path -LiteralPath $latest) {
    return
  }

  $target = Get-ChildItem -LiteralPath $cacheRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'latest' -and (Test-Path -LiteralPath (Join-Path $_.FullName '.codex-plugin\plugin.json')) } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

  if (-not $target) {
    return
  }

  Write-Step "creating missing computer-use latest junction -> $($target.FullName)"
  New-Item -ItemType Junction -Path $latest -Target $target.FullName | Out-Null
}

function Test-ComputerUseHelperTransport {
  param([string]$CodexHomePath)

  $helperTransportPath = Join-Path $CodexHomePath 'plugins\cache\openai-bundled\computer-use\latest\node_modules\@oai\sky\dist\project\cua\sky_js\src\targets\windows\internal\helper_transport.js'
  if (-not (Test-Path -LiteralPath $helperTransportPath -PathType Leaf)) {
    throw "missing Computer Use helper transport path: $helperTransportPath"
  }

  $node = Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $node) {
    throw 'node.exe not found; cannot verify local Computer Use helper transport'
  }

  $script = @'
import { pathToFileURL } from "node:url";

const modulePath = process.argv[2];
const mod = await import(pathToFileURL(modulePath).href);
if (typeof mod.WindowsHelperTransport !== "function") {
  throw new Error("WindowsHelperTransport export is missing");
}

const transport = new mod.WindowsHelperTransport();
try {
  const info = await transport.request("screenInfo", {});
  if (!info || typeof info.width !== "number" || typeof info.height !== "number" || info.width <= 0 || info.height <= 0) {
    throw new Error(`invalid screenInfo response: ${JSON.stringify(info)}`);
  }

  const screenshot = await transport.request("screenshot", {});
  if (!screenshot || screenshot.mimeType !== "image/png" || typeof screenshot.data !== "string" || screenshot.data.length < 100) {
    throw new Error("invalid screenshot response");
  }

  console.log(JSON.stringify({ ok: true, width: info.width, height: info.height, screenshotBytesApprox: Math.floor(screenshot.data.length * 3 / 4) }));
} finally {
  if (typeof transport.close === "function") {
    await transport.close();
  }
}
'@

  $temp = Join-Path $env:TEMP ('codex-computer-use-verify-' + [guid]::NewGuid().ToString('N') + '.mjs')
  try {
    [System.IO.File]::WriteAllText($temp, $script, [System.Text.UTF8Encoding]::new($false))
    $output = & $node.Source $temp $helperTransportPath 2>&1
    if ($LASTEXITCODE -ne 0) {
      throw "Computer Use helper transport verification failed for $helperTransportPath`: $($output | Out-String)"
    }
    if ($output) {
      $outputText = ($output | Out-String).Trim()
      Write-Step "helper transport ok: $outputText"
    }
  } finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
  }
}

function Ensure-ChromeLatestJunction {
  param([string]$CodexHomePath)

  $cacheRoot = Join-Path $CodexHomePath 'plugins\cache\openai-bundled\chrome'
  if (-not (Test-Path -LiteralPath $cacheRoot -PathType Container)) {
    return
  }

  $latest = Join-Path $cacheRoot 'latest'
  $requiredRelativePaths = @(
    'scripts\browser-client.mjs',
    'extension-host\windows\x64\extension-host.exe'
  )

  if (Test-Path -LiteralPath $latest) {
    $latestOk = $true
    foreach ($relativePath in $requiredRelativePaths) {
      if (-not (Test-Path -LiteralPath (Join-Path $latest $relativePath) -PathType Leaf)) {
        $latestOk = $false
        break
      }
    }

    if ($latestOk) {
      return
    }

    $latestItem = Get-Item -LiteralPath $latest -Force
    if (($latestItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
      throw "chrome latest path exists but is not a junction: $latest"
    }
    Remove-Item -LiteralPath $latest -Force
  }

  $target = Get-ChildItem -LiteralPath $cacheRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object {
      if ($_.Name -eq 'latest') {
        return $false
      }
      foreach ($relativePath in $requiredRelativePaths) {
        if (-not (Test-Path -LiteralPath (Join-Path $_.FullName $relativePath) -PathType Leaf)) {
          return $false
        }
      }
      return $true
    } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

  if (-not $target) {
    return
  }

  Write-Step "creating missing chrome latest junction -> $($target.FullName)"
  New-Item -ItemType Junction -Path $latest -Target $target.FullName | Out-Null
}

function Assert-ChildPath {
  param(
    [string]$ParentPath,
    [string]$ChildPath,
    [string]$Description
  )

  $parentFull = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ParentPath).Path).TrimEnd('\')
  $childFull = [System.IO.Path]::GetFullPath($ChildPath).TrimEnd('\')
  if (-not $childFull.StartsWith($parentFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "$Description is outside $parentFull`: $childFull"
  }
}

function Sync-PersistentOpenAiBundledMarketplace {
  param(
    [string]$CodexHomePath,
    [string]$SourceRoot,
    [string]$TargetRoot
  )

  if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    throw "repaired openai-bundled marketplace source missing: $SourceRoot"
  }

  foreach ($required in @(
      '.agents\plugins\marketplace.json',
      'plugins\computer-use\.codex-plugin\plugin.json',
      'plugins\chrome\.codex-plugin\plugin.json'
    )) {
    $requiredPath = Join-Path $SourceRoot $required
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
      throw "repaired openai-bundled marketplace is incomplete: $requiredPath"
    }
  }

  Assert-ChildPath $CodexHomePath $TargetRoot 'persistent openai-bundled marketplace root'
  $targetFull = [System.IO.Path]::GetFullPath($TargetRoot)
  if ($targetFull -match '\\\.tmp(\\|$)') {
    throw "persistent openai-bundled marketplace root must not be under .tmp: $targetFull"
  }

  if (Test-Path -LiteralPath $TargetRoot) {
    Remove-Item -LiteralPath $TargetRoot -Recurse -Force
  }

  New-Item -ItemType Directory -Path $TargetRoot | Out-Null
  Get-ChildItem -LiteralPath $SourceRoot -Force | Copy-Item -Destination $TargetRoot -Recurse -Force
  Write-Step "synced persistent openai-bundled marketplace: $TargetRoot"
}

function Set-OpenAiBundledMarketplaceSource {
  param(
    [string]$CodexHomePath,
    [string]$MarketplaceRoot
  )

  $configPath = Join-Path $CodexHomePath 'config.toml'
  if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "config.toml not found: $configPath"
  }

  $resolvedMarketplaceRoot = (Resolve-Path -LiteralPath $MarketplaceRoot).Path
  $sourceValue = "\\?\$resolvedMarketplaceRoot"
  $sourceToml = $sourceValue.Replace("'", "''")
  $lastUpdated = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

  $lines = [System.Collections.Generic.List[string]]::new()
  foreach ($line in [System.IO.File]::ReadAllLines($configPath)) {
    $lines.Add($line)
  }

  $header = '[marketplaces.openai-bundled]'
  $start = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -eq $header) {
      $start = $i
      break
    }
  }

  if ($start -lt 0) {
    if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
      $lines.Add('')
    }
    $lines.Add($header)
    $lines.Add("last_updated = '$lastUpdated'")
    $lines.Add("source = '$sourceToml'")
    $lines.Add("source_type = 'local'")
    [System.IO.File]::WriteAllLines($configPath, $lines)
    Write-Step "pointed openai-bundled marketplace at persistent source: $sourceValue"
    return
  }

  $end = $lines.Count
  for ($i = $start + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i].TrimStart().StartsWith('[')) {
      $end = $i
      break
    }
  }

  $desired = [ordered]@{
    last_updated = "last_updated = '$lastUpdated'"
    source = "source = '$sourceToml'"
    source_type = "source_type = 'local'"
  }

  foreach ($key in @($desired.Keys)) {
    $found = $false
    for ($i = $start + 1; $i -lt $end; $i++) {
      if ($lines[$i] -match "^\s*$([regex]::Escape($key))\s*=") {
        $lines[$i] = $desired[$key]
        $found = $true
        break
      }
    }
    if (-not $found) {
      $lines.Insert($end, $desired[$key])
      $end++
    }
  }

  [System.IO.File]::WriteAllLines($configPath, $lines)
  Write-Step "pointed openai-bundled marketplace at persistent source: $sourceValue"
}

function Assert-PluginInstalled {
  param(
    [string]$PluginList,
    [string]$PluginName
  )
  $pattern = [regex]::Escape($PluginName) + '\s+installed,\s+enabled'
  if ($PluginList -notmatch $pattern) {
    throw "$PluginName is not installed and enabled"
  }
}

$resolvedRepairScript = Resolve-RepairScript $RepairScript
if (-not $resolvedRepairScript) {
  throw 'install-computer-use-local.ps1 was not found; restore codex-windows-fast-patch-skill or pass -RepairScript.'
}

if ([string]::IsNullOrWhiteSpace($PersistentMarketplaceRoot)) {
  $PersistentMarketplaceRoot = Join-Path $CodexHome 'bundled-marketplaces\openai-bundled'
}

Write-Step "using repair script: $resolvedRepairScript"

if ($StrictVerifyOnly) {
  Ensure-ComputerUseLatestJunction $CodexHome
  Ensure-ChromeLatestJunction $CodexHome
  Test-ComputerUseHelperTransport $CodexHome

  $pluginList = Invoke-CodexText @('plugin', 'list')
  Assert-PluginInstalled $pluginList 'computer-use@openai-bundled'
  Assert-PluginInstalled $pluginList 'chrome@openai-bundled'
  $sandbox = Invoke-CodexText @('sandbox', 'C:\Windows\System32\cmd.exe', '/c', 'echo', 'OK')
  if ($sandbox -notmatch '\bOK\b') {
    throw 'codex sandbox did not return OK'
  }
  Write-Step 'strict verification ok'
  exit 0
}

Write-Step 'repairing computer-use and bundled marketplace mirror'
& powershell -NoProfile -ExecutionPolicy Bypass -File $resolvedRepairScript -VerifyOnly
if ($LASTEXITCODE -ne 0) {
  throw 'computer-use repair script failed'
}

Ensure-ComputerUseLatestJunction $CodexHome

if (-not $SkipChromeAdd) {
  Write-Step 'installing chrome@openai-bundled from repaired marketplace'
  Invoke-CodexText @('plugin', 'add', 'chrome@openai-bundled') | Out-Null
  Ensure-ChromeLatestJunction $CodexHome
}

$temporaryMarketplaceRoot = Join-Path $CodexHome '.tmp\bundled-marketplaces\openai-bundled'
Sync-PersistentOpenAiBundledMarketplace $CodexHome $temporaryMarketplaceRoot $PersistentMarketplaceRoot
Set-OpenAiBundledMarketplaceSource $CodexHome $PersistentMarketplaceRoot

if (-not $SkipComputerUseAdd) {
  $pluginListBeforeComputerUse = Invoke-CodexText @('plugin', 'list')
  if ($pluginListBeforeComputerUse -notmatch 'computer-use@openai-bundled\s+installed,\s+enabled') {
    Write-Step 'installing computer-use@openai-bundled from repaired marketplace'
    Invoke-CodexText @('plugin', 'add', 'computer-use@openai-bundled') | Out-Null
    Ensure-ComputerUseLatestJunction $CodexHome
  }
}

Write-Step 'checking plugin status'
$pluginList = Invoke-CodexText @('plugin', 'list')
Assert-PluginInstalled $pluginList 'computer-use@openai-bundled'
Assert-PluginInstalled $pluginList 'chrome@openai-bundled'

Write-Step 'checking sandbox'
$sandboxOutput = Invoke-CodexText @('sandbox', 'C:\Windows\System32\cmd.exe', '/c', 'echo', 'OK')
if ($sandboxOutput -notmatch '\bOK\b') {
  throw 'codex sandbox did not return OK'
}

Write-Step 'running strict helper verification'
Ensure-ComputerUseLatestJunction $CodexHome
Ensure-ChromeLatestJunction $CodexHome
Test-ComputerUseHelperTransport $CodexHome

$chromeClient = Join-Path $CodexHome 'plugins\cache\openai-bundled\chrome\latest\scripts\browser-client.mjs'
$chromeHost = Join-Path $CodexHome 'plugins\cache\openai-bundled\chrome\latest\extension-host\windows\x64\extension-host.exe'
foreach ($path in @($chromeClient, $chromeHost)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "missing Chrome plugin path: $path"
  }
}

Write-Step 'repair complete; fully quit and reopen Codex Desktop before using repaired native pipe capabilities'
