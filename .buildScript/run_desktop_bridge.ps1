<#
.SYNOPSIS
    Launch the JsxposedX desktop client wired to the phone over USB.

.DESCRIPTION
    Steps:
      1. resolve the adb target device
      2. ask the phone to bring JsxposedX to the foreground (the bridge lives in the app process)
      3. read the bridge token from logcat (only readable by someone who already holds adb)
      4. forward a local TCP port to the phone's abstract socket
      5. run the Flutter desktop entry point, passing port and token via --dart-define
      6. remove the port forward on exit

    See docs/desktop_bridge_CN.md for the full design.

.EXAMPLE
    .\.buildScript\run_desktop_bridge.ps1

.EXAMPLE
    .\.buildScript\run_desktop_bridge.ps1 -DeviceId emulator-5554 -Port 27183 -Release

.EXAMPLE
    .\.buildScript\run_desktop_bridge.ps1 -SkipLaunch
#>
param(
    [string]$DeviceId = "",
    [int]$Port = 27183,
    [string]$Token = "",
    [switch]$Release,
    [switch]$SkipLaunch,
    [switch]$KeepForward
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

# Must match BridgeProtocol.kt / bridge_protocol.dart
$appId = "com.jsxposed.x"
$socketName = "jsxposed_desktop_bridge"
$logTag = "JsxposedX-DesktopBridge"
$desktopEntry = "lib/desktop/main_desktop.dart"

function Write-Step([string]$Message) {
    Write-Host "[bridge] $Message" -ForegroundColor Cyan
}

function Fail([string]$Message) {
    Write-Host "[bridge] ERROR: $Message" -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------------ adb
$adbPath = $null
$adbCommand = Get-Command adb -ErrorAction SilentlyContinue
if ($adbCommand) {
    $adbPath = $adbCommand.Source
} else {
    $candidates = @()
    if ($env:ANDROID_HOME) { $candidates += (Join-Path $env:ANDROID_HOME "platform-tools\adb.exe") }
    if ($env:ANDROID_SDK_ROOT) { $candidates += (Join-Path $env:ANDROID_SDK_ROOT "platform-tools\adb.exe") }
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe") }
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { $adbPath = $candidate; break }
    }
}
if (-not $adbPath) {
    Fail "adb not found. Install Android platform-tools or add adb to PATH."
}
Write-Step "adb: $adbPath"

# --------------------------------------------------------------- device
$serial = $DeviceId
if (-not $serial -and $env:ANDROID_SERIAL) { $serial = $env:ANDROID_SERIAL }
if (-not $serial) {
    $deviceLines = & $adbPath devices | Select-Object -Skip 1 | Where-Object { $_ -match "\tdevice$" }
    $serials = @($deviceLines | ForEach-Object { ($_ -split "\s+")[0] })
    if ($serials.Count -eq 0) {
        Fail "No device in 'device' state. Enable USB debugging on the phone and reconnect it."
    }
    if ($serials.Count -gt 1) {
        Fail ("Multiple devices found: " + ($serials -join ", ") + ". Pass -DeviceId <serial>.")
    }
    $serial = $serials[0]
}
Write-Step "device: $serial"

# ------------------------------------------------- start the phone app
$null = & $adbPath -s $serial shell am start -n "$appId/.MainActivity" 2>$null
Write-Step "asked the phone to open $appId (bridge socket is created with the Flutter engine)"

# ------------------------------------------------------------ read token
if (-not $Token) {
    Write-Step "reading bridge token from logcat ..."
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        $dump = & $adbPath -s $serial logcat -d -t 3000 -s $logTag 2>$null
        $hit = $dump | Select-String -Pattern "token=([0-9a-fA-F]{32})" | Select-Object -Last 1
        if ($hit) {
            $Token = $hit.Matches[0].Groups[1].Value
            break
        }
        Start-Sleep -Milliseconds 700
    }
}
if (-not $Token) {
    Fail ("Token not found in logcat. Make sure JsxposedX is running on the phone " +
          "(it logs one token per start), or pass -Token <value>.")
}
Write-Step "token: $Token"

# --------------------------------------------------------------- forward
$null = & $adbPath -s $serial forward --remove "tcp:$Port" 2>$null
& $adbPath -s $serial forward "tcp:$Port" "localabstract:$socketName" | Out-Null
Write-Step "forward: tcp:$Port -> localabstract:$socketName"

# ---------------------------------------------------------------- launch
$definePort = "--dart-define=BRIDGE_PORT=$Port"
$defineToken = "--dart-define=BRIDGE_TOKEN=$Token"

if ($SkipLaunch) {
    Write-Step "port forward is ready; not launching the desktop client (-SkipLaunch)."
    Write-Host ""
    Write-Host "flutter run -d windows -t $desktopEntry $definePort $defineToken"
    Write-Host ""
    Write-Host "adb -s $serial forward --remove tcp:$Port"
    exit 0
}

$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCommand) {
    Fail "flutter not found in PATH."
}

$flutterArgs = @("run", "-d", "windows", "-t", $desktopEntry, $definePort, $defineToken)
if ($Release) { $flutterArgs += "--release" }

Write-Step "launching desktop client ..."
try {
    & flutter @flutterArgs
} finally {
    if (-not $KeepForward) {
        $null = & $adbPath -s $serial forward --remove "tcp:$Port" 2>$null
        Write-Step "port forward removed"
    } else {
        Write-Step "port forward kept (-KeepForward): tcp:$Port"
    }
}
