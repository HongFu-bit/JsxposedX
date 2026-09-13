<#
.SYNOPSIS
    Build a distributable JsxposedX desktop bundle for Windows.

.DESCRIPTION
    Steps:
      1. flutter build windows --release with the desktop entry point
      2. assemble a clean folder under build/desktop/JsxposedX
      3. bundle adb (platform-tools) into the folder, so the exe can set up the
         USB port forward and read the token on its own
      4. write a short README.txt and zip the folder for sharing

    The resulting exe connects to the phone by itself: it finds adb, opens
    JsxposedX on the phone, runs "adb forward", reads the bridge token from
    logcat, then connects. See docs/desktop_bridge_CN.md.

.PARAMETER AdbPath
    Directory that contains adb.exe (platform-tools). If omitted, ANDROID_HOME /
    ANDROID_SDK_ROOT / %LOCALAPPDATA%\Android\Sdk are searched.

.PARAMETER Flutter
    Flutter SDK location: the SDK root (e.g. C:\flutter), its bin directory, or
    flutter.bat itself. Use this when "flutter" is not on PATH.

.PARAMETER SkipAdb
    Do not bundle adb. The app will then rely on adb being in PATH.

.PARAMETER SkipBuild
    Reuse the existing build output instead of running flutter build.

.PARAMETER NoZip
    Do not create the distributable zip.

.EXAMPLE
    .\.buildScript\build_desktop_exe.ps1

.EXAMPLE
    .\.buildScript\build_desktop_exe.ps1 -SkipBuild -NoZip

.NOTES
    Build machine requirements:
      - Flutter SDK
      - Visual Studio with "Desktop development with C++" (MSVC toolchain)
      - Android platform-tools (only for bundling adb)

    End user requirements:
      - Windows 10 1809 or newer, x64
      - Microsoft Visual C++ 2015-2022 Redistributable (x64)
#>
param(
    [string]$AdbPath = "",
    [string]$Flutter = "",
    [switch]$SkipAdb,
    [switch]$SkipBuild,
    [switch]$NoZip
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$desktopEntry = "lib/desktop/main_desktop.dart"
$releaseDir = "build/windows/x64/runner/Release"
$outputDir = "build/desktop/JsxposedX"
$exeName = "JsxposedX.exe"
$legacyExeName = "jsxposed_x.exe"

function Write-Step([string]$Message) {
    Write-Host "[exe] $Message" -ForegroundColor Cyan
}

function Write-Warn([string]$Message) {
    Write-Host "[exe] WARNING: $Message" -ForegroundColor Yellow
}

function Fail([string]$Message) {
    Write-Host "[exe] ERROR: $Message" -ForegroundColor Red
    exit 1
}

# Locate flutter.bat. Lookup order:
#   1) -Flutter <sdk dir | bin dir | flutter.bat>
#   2) PATH
#   3) FLUTTER_ROOT
#   4) .fvm/flutter_sdk in the repo (FVM)
#   5) flutter.sdk recorded in android/local.properties
#   6) common install locations
function Resolve-Flutter([string]$Hint) {
    if ($Hint) {
        if (Test-Path $Hint -PathType Container) {
            foreach ($sub in @("bin\flutter.bat", "flutter.bat")) {
                $candidate = Join-Path $Hint $sub
                if (Test-Path $candidate) { return $candidate }
            }
        } elseif (Test-Path $Hint) {
            return $Hint
        }
        Fail "-Flutter points to nothing usable: $Hint (expected the SDK folder, its bin folder, or flutter.bat)"
    }

    $command = Get-Command flutter -ErrorAction SilentlyContinue
    if ($command -and $command.Source -and (Test-Path $command.Source)) {
        return $command.Source
    }

    if ($env:FLUTTER_ROOT) {
        $candidate = Join-Path $env:FLUTTER_ROOT "bin\flutter.bat"
        if (Test-Path $candidate) { return $candidate }
    }

    $fvmSdk = Join-Path $repoRoot ".fvm\flutter_sdk\bin\flutter.bat"
    if (Test-Path $fvmSdk) { return $fvmSdk }

    $localProperties = Join-Path $repoRoot "android\local.properties"
    if (Test-Path $localProperties) {
        $line = Select-String -Path $localProperties -Pattern '^flutter\.sdk\s*=\s*(.+)$' |
            Select-Object -First 1
        if ($line) {
            $sdk = $line.Matches[0].Groups[1].Value.Trim().Replace('\\', '\')
            $candidate = Join-Path $sdk "bin\flutter.bat"
            if (Test-Path $candidate) { return $candidate }
        }
    }

    $common = @()
    if ($env:LOCALAPPDATA) { $common += (Join-Path $env:LOCALAPPDATA "flutter") }
    if ($env:USERPROFILE) {
        $common += (Join-Path $env:USERPROFILE "flutter")
        $common += (Join-Path $env:USERPROFILE "fvm\default")
        $common += (Join-Path $env:USERPROFILE "scoop\apps\flutter\current")
    }
    $common += "C:\flutter"
    $common += "C:\src\flutter"
    $common += "C:\tools\flutter"
    foreach ($directory in $common) {
        $candidate = Join-Path $directory "bin\flutter.bat"
        if (Test-Path $candidate) { return $candidate }
    }

    return $null
}

# --------------------------------------------------------------- version
$version = "0.0.0"
$versionLine = Select-String -Path "pubspec.yaml" -Pattern '^version:\s*(.+)$' |
    Select-Object -First 1
if ($versionLine) {
    $version = ($versionLine.Matches[0].Groups[1].Value -split '\+')[0].Trim()
}
Write-Step "version: $version"

# ----------------------------------------------------------------- build
if (-not $SkipBuild) {
    $flutterExe = Resolve-Flutter $Flutter
    if (-not $flutterExe) {
        Fail ("flutter not found. Tried: -Flutter, PATH, FLUTTER_ROOT, .fvm/flutter_sdk, " +
              "android/local.properties, and common install locations. " +
              "Either add <flutter sdk>\bin to PATH and reopen PowerShell, " +
              "or run with -Flutter <flutter sdk path> (e.g. -Flutter C:\flutter).")
    }
    Write-Step "flutter: $flutterExe"
    Write-Step "building release (this takes a few minutes) ..."
    & $flutterExe build windows --release -t $desktopEntry
    if ($LASTEXITCODE -ne 0) {
        Fail "flutter build failed with exit code $LASTEXITCODE."
    }
}

if (-not (Test-Path $releaseDir)) {
    Fail "release output not found: $releaseDir"
}

# --------------------------------------------------------------- assemble
if (Test-Path $outputDir) {
    Remove-Item -Path $outputDir -Recurse -Force
}
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
Copy-Item -Path (Join-Path $releaseDir "*") -Destination $outputDir -Recurse -Force
Write-Step "assembled: $outputDir"

$builtExe = Join-Path $outputDir $exeName
if (-not (Test-Path $builtExe)) {
    $legacyExe = Join-Path $outputDir $legacyExeName
    if (Test-Path $legacyExe) {
        # Fallback for a stale build that still uses the old BINARY_NAME
        Move-Item -Path $legacyExe -Destination $builtExe -Force
        Write-Step "renamed $legacyExeName -> $exeName"
    } else {
        Fail "executable not found in $outputDir (expected $exeName)."
    }
}

# ------------------------------------------------------------ bundle adb
if (-not $SkipAdb) {
    $adbSource = $AdbPath
    $adbPathWasGiven = [bool]$AdbPath

    if ($adbSource -and $adbSource.EndsWith("adb.exe") -and (Test-Path $adbSource)) {
        $adbSource = Split-Path -Parent $adbSource
    }

    if (-not $adbSource) {
        $candidates = @()
        if ($env:ANDROID_HOME) { $candidates += (Join-Path $env:ANDROID_HOME "platform-tools") }
        if ($env:ANDROID_SDK_ROOT) { $candidates += (Join-Path $env:ANDROID_SDK_ROOT "platform-tools") }
        if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools") }
        foreach ($candidate in $candidates) {
            if (Test-Path (Join-Path $candidate "adb.exe")) {
                $adbSource = $candidate
                break
            }
        }
    }

    if ($adbSource -and (Test-Path (Join-Path $adbSource "adb.exe"))) {
        $adbTarget = Join-Path $outputDir "platform-tools"
        New-Item -ItemType Directory -Path $adbTarget -Force | Out-Null
        Copy-Item -Path (Join-Path $adbSource "adb.exe") -Destination $adbTarget -Force
        foreach ($dll in @("AdbWinApi.dll", "AdbWinUsbApi.dll")) {
            $dllPath = Join-Path $adbSource $dll
            if (Test-Path $dllPath) {
                Copy-Item -Path $dllPath -Destination $adbTarget -Force
            }
        }
        Write-Step "bundled adb from: $adbSource"
    } elseif ($adbPathWasGiven) {
        # 用户明确指定了来源却找不到，直接失败，避免"以为打进去了"的错觉
        Fail "-AdbPath does not contain adb.exe: $AdbPath (point it at the platform-tools folder)"
    } else {
        Write-Warn "adb.exe not found; the app will fall back to adb in PATH. Pass -AdbPath <platform-tools folder> to bundle it."
    }
}

# ---------------------------------------------------------------- readme
$readme = @"
JsxposedX desktop client (version $version, windows x64)
=======================================================

How to run
----------
1. Connect the phone over USB and enable USB debugging.
2. Double-click JsxposedX.exe.
3. Press "Connect to phone". The app will:
     - find adb (the bundled platform-tools folder is used first)
     - open JsxposedX on the phone
     - set up the USB port forward
     - read the connection token from logcat
     - connect and show the same UI as the phone app

The phone app has to be installed on the device; this desktop client only
mirrors its UI and runs all native work on the phone.

If connecting fails
-------------------
- "No device detected": check the USB cable, USB debugging, and accept the
  authorization prompt on the phone.
- "adb not found": put the Android SDK platform-tools folder here as
  platform-tools\, or add adb to PATH.
- Multiple devices: keep a single device connected and retry.
- If the connection token cannot be read, the app restarts JsxposedX on the
  phone once to regenerate it.

Requirements
------------
- Windows 10 1809 or newer (x64)
- Microsoft Visual C++ 2015-2022 Redistributable (x64). If Windows reports a
  missing VCRUNTIME140.dll, install it from Microsoft.

This client mirrors the phone app: all native work (hooks, memory tools, APK
and SO analysis) runs on the phone, over the USB connection.
"@
Set-Content -Path (Join-Path $outputDir "README.txt") -Value $readme -Encoding ASCII
Write-Step "wrote README.txt"

# ------------------------------------------------------------------- zip
if (-not $NoZip) {
    $zipPath = "build/desktop/JsxposedX-$version-windows-x64.zip"
    if (Test-Path $zipPath) {
        Remove-Item -Path $zipPath -Force
    }
    Compress-Archive -Path $outputDir -DestinationPath $zipPath
    Write-Step "zip: $zipPath"
}

# ---------------------------------------------------------------- summary
Write-Host ""
Write-Step "done."
Write-Host "  folder : $outputDir"
Write-Host "  exe    : $outputDir\$exeName"
if (-not $NoZip) {
    Write-Host "  zip    : build/desktop/JsxposedX-$version-windows-x64.zip"
}
Write-Host ""
Write-Host "  Distribute the whole folder (or the zip) - the exe needs the data\ folder and the DLLs next to it." -ForegroundColor DarkGray
