[CmdletBinding()]
param(
  [string]$CodexHome = (Join-Path $env:USERPROFILE '.codex'),
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

Write-Step "using repair script: $resolvedRepairScript"

if ($StrictVerifyOnly) {
  Ensure-ComputerUseLatestJunction $CodexHome
  & powershell -NoProfile -ExecutionPolicy Bypass -File $resolvedRepairScript -StrictVerifyOnly
  if ($LASTEXITCODE -ne 0) {
    throw 'strict computer-use verification failed'
  }

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
}

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
& powershell -NoProfile -ExecutionPolicy Bypass -File $resolvedRepairScript -StrictVerifyOnly
if ($LASTEXITCODE -ne 0) {
  throw 'strict computer-use verification failed after repair'
}

$chromeClient = Join-Path $CodexHome 'plugins\cache\openai-bundled\chrome\latest\scripts\browser-client.mjs'
$chromeHost = Join-Path $CodexHome 'plugins\cache\openai-bundled\chrome\latest\extension-host\windows\x64\extension-host.exe'
foreach ($path in @($chromeClient, $chromeHost)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "missing Chrome plugin path: $path"
  }
}

Write-Step 'repair complete; fully quit and reopen Codex Desktop before using repaired native pipe capabilities'
