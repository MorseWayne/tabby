param(
    [ValidateSet('x64', 'arm64')]
    [string]$Arch = 'x64'
)

$ErrorActionPreference = 'Continue'

$requiredFailures = 0
$warnings = 0

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK]   $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    $script:warnings++
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    $script:requiredFailures++
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Get-CommandPath {
    param([string]$Name)

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    return $null
}

function Test-Command {
    param(
        [string]$Name,
        [string]$DisplayName = $Name,
        [switch]$Required
    )

    $path = Get-CommandPath $Name
    if ($path) {
        Write-Ok "$DisplayName found: $path"
        return $true
    }

    if ($Required) {
        Write-Fail "$DisplayName not found in PATH"
    } else {
        Write-Warn "$DisplayName not found in PATH"
    }

    return $false
}

function Get-VersionOutput {
    param(
        [string]$Command,
        [string[]]$Arguments
    )

    try {
        $output = & $Command @Arguments 2>$null
        if ($LASTEXITCODE -eq 0 -or $output) {
            return ($output | Select-Object -First 1)
        }
    } catch {
        return $null
    }

    return $null
}

function Compare-SemverMajor {
    param(
        [string]$VersionText,
        [int]$ExpectedMajor
    )

    if ($VersionText -match 'v?(\d+)\.') {
        return ([int]$Matches[1] -eq $ExpectedMajor)
    }

    return $false
}

Write-Host ''
Write-Host 'Tabby Windows local build environment check' -ForegroundColor White
Write-Host "Target arch: $Arch" -ForegroundColor White
Write-Host ''

if ($env:OS -ne 'Windows_NT') {
    Write-Fail 'This script must be run on Windows'
} else {
    Write-Ok 'Running on Windows'
}

Write-Info "PowerShell: $($PSVersionTable.PSVersion)"

if (-not (Test-Path 'package.json')) {
    Write-Fail 'package.json not found. Run this script from the repository root.'
} else {
    Write-Ok 'Repository root looks valid'
}

Write-Host ''
Write-Host 'Checking basic tools...' -ForegroundColor White

Test-Command git 'Git' -Required | Out-Null
Test-Command node 'Node.js' -Required | Out-Null
Test-Command npm 'npm' -Required | Out-Null

$nodeVersion = Get-VersionOutput node @('--version')
if ($nodeVersion) {
    if (Compare-SemverMajor $nodeVersion 22) {
        Write-Ok "Node.js version is $nodeVersion"
    } else {
        Write-Fail "Node.js version is $nodeVersion, but this repo expects Node 22"
    }
}

$npmVersion = Get-VersionOutput npm @('--version')
if ($npmVersion) {
    Write-Ok "npm version is $npmVersion"
}

$yarnPath = Get-CommandPath yarn
if ($yarnPath) {
    $yarnVersion = Get-VersionOutput yarn @('--version')
    if ($yarnVersion -match '^1\.') {
        Write-Ok "Yarn v1 found: $yarnVersion"
    } else {
        Write-Fail "Yarn version is $yarnVersion, but this repo expects Yarn v1"
    }
} else {
    Write-Fail 'Yarn not found. Install with: npm i -g yarn'
}

$nodeGypPath = Get-CommandPath node-gyp
if ($nodeGypPath) {
    $nodeGypVersion = Get-VersionOutput node-gyp @('--version')
    Write-Ok "node-gyp found: $nodeGypVersion"
} else {
    Write-Warn 'node-gyp not found globally. CI installs it with: npm install --global node-gyp@10.2.0'
}

Write-Host ''
Write-Host 'Checking Python for node-gyp...' -ForegroundColor White

$pyPath = Get-CommandPath py
$pythonPath = Get-CommandPath python

if ($pyPath) {
    $pyVersion = Get-VersionOutput py @('-3', '--version')
    if ($pyVersion) {
        Write-Ok "Python launcher found: $pyVersion"
    } else {
        Write-Warn 'Python launcher found, but py -3 --version failed'
    }
} elseif ($pythonPath) {
    $pythonVersion = Get-VersionOutput python @('--version')
    if ($pythonVersion -match 'Python 3\.') {
        Write-Ok "Python found: $pythonVersion"
    } else {
        Write-Fail "Python found but not Python 3: $pythonVersion"
    }
} else {
    Write-Fail 'Python 3 not found. node-gyp requires Python.'
}

Write-Host ''
Write-Host 'Checking Rust toolchain...' -ForegroundColor White

Test-Command rustup 'rustup' -Required | Out-Null
Test-Command cargo 'cargo' -Required | Out-Null
Test-Command rustc 'rustc' -Required | Out-Null

$rustcVersion = Get-VersionOutput rustc @('--version')
if ($rustcVersion) {
    Write-Ok "rustc version: $rustcVersion"
}

$rustTarget = if ($Arch -eq 'arm64') {
    'aarch64-pc-windows-msvc'
} else {
    'x86_64-pc-windows-msvc'
}

try {
    $installedTargets = rustup target list --installed 2>$null
    if ($installedTargets -contains $rustTarget) {
        Write-Ok "Rust target installed: $rustTarget"
    } else {
        Write-Fail "Rust target missing: $rustTarget. Install with: rustup target add $rustTarget"
    }
} catch {
    Write-Fail 'Could not query rustup targets'
}

Write-Host ''
Write-Host 'Checking Visual Studio Build Tools / MSVC...' -ForegroundColor White

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"

if (Test-Path $vswhere) {
    Write-Ok "vswhere found: $vswhere"

    $vsInstall = & $vswhere `
        -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath `
        -latest 2>$null

    if ($vsInstall) {
        Write-Ok "Visual Studio with MSVC tools found: $vsInstall"

        $vcvars = Join-Path $vsInstall 'VC\Auxiliary\Build\vcvars64.bat'
        if (Test-Path $vcvars) {
            Write-Ok 'vcvars64.bat found'
        } else {
            Write-Warn 'vcvars64.bat not found under Visual Studio installation'
        }
    } else {
        Write-Fail 'Visual Studio Build Tools with MSVC C++ tools not found'
    }
} else {
    Write-Fail 'vswhere not found. Visual Studio Build Tools may be missing.'
}

$clPath = Get-CommandPath cl
if ($clPath) {
    Write-Ok "cl.exe found in current shell: $clPath"
} else {
    Write-Warn 'cl.exe is not in PATH. This is okay if node-gyp can find Visual Studio, but a Developer PowerShell is safer.'
}

$msbuildPath = Get-CommandPath msbuild
if ($msbuildPath) {
    Write-Ok "MSBuild found in PATH: $msbuildPath"
} else {
    Write-Warn 'MSBuild not found in PATH. Visual Studio Build Tools may still work through node-gyp auto-detection.'
}

Write-Host ''
Write-Host 'Checking Windows SDK...' -ForegroundColor White

$kitsRoot = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
$signtoolCandidates = @()

if (Test-Path $kitsRoot) {
    $signtoolCandidates = Get-ChildItem -Path $kitsRoot -Filter 'signtool.exe' -Recurse -ErrorAction SilentlyContinue
}

if ($signtoolCandidates.Count -gt 0) {
    $latestSigntool = $signtoolCandidates | Sort-Object FullName -Descending | Select-Object -First 1
    Write-Ok "Windows SDK tools found, example signtool: $($latestSigntool.FullName)"
} else {
    Write-Warn 'Windows SDK signtool.exe not found. Unsigned local builds may still work; signing needs SDK tools.'
}

Write-Host ''
Write-Host 'Checking repository dependencies...' -ForegroundColor White

if (Test-Path 'node_modules') {
    Write-Ok 'Root node_modules exists'
} else {
    Write-Warn 'Root node_modules missing. Run: yarn --network-timeout 1000000'
}

if (Test-Path 'app\node_modules') {
    Write-Ok 'app/node_modules exists'
} else {
    Write-Warn 'app/node_modules missing. Full install/build may create or require it.'
}

if (Test-Path 'scripts\build-windows.mjs') {
    Write-Ok 'Windows build script found: scripts/build-windows.mjs'
} else {
    Write-Fail 'Windows build script missing: scripts/build-windows.mjs'
}

if (Test-Path 'scripts\prepackage-plugins.mjs') {
    Write-Ok 'Plugin prepackage script found'
} else {
    Write-Fail 'Plugin prepackage script missing: scripts/prepackage-plugins.mjs'
}

Write-Host ''
Write-Host 'Checking optional signing tools...' -ForegroundColor White

$smctlPath = Get-CommandPath smctl
if ($smctlPath) {
    Write-Ok "DigiCert smctl found: $smctlPath"
} else {
    Write-Warn 'DigiCert smctl not found. This is fine for unsigned local builds.'
}

$signingEnvVars = @(
    'SM_CLIENT_CERT_PASSWORD',
    'SM_API_KEY',
    'SM_HOST',
    'SM_CODE_SIGNING_CERT_SHA1_HASH',
    'SM_KEYPAIR_ALIAS'
)

$missingSigningVars = @()
foreach ($name in $signingEnvVars) {
    if (-not [Environment]::GetEnvironmentVariable($name)) {
        $missingSigningVars += $name
    }
}

if ($missingSigningVars.Count -eq 0) {
    Write-Ok 'Signing environment variables are present'
} else {
    Write-Warn "Signing environment variables missing: $($missingSigningVars -join ', '). This is fine for unsigned local builds."
}

Write-Host ''
Write-Host 'Suggested unsigned local build commands:' -ForegroundColor White
Write-Host "  `$env:ARCH = `"$Arch`""
Write-Host '  npm i -g yarn node-gyp@10.2.0'
Write-Host '  yarn --network-timeout 1000000'
Write-Host '  yarn run build'
Write-Host '  node scripts/prepackage-plugins.mjs'
Write-Host '  node scripts/build-windows.mjs'

Write-Host ''
Write-Host 'Summary' -ForegroundColor White
Write-Host "Required failures: $requiredFailures"
Write-Host "Warnings: $warnings"

if ($requiredFailures -gt 0) {
    Write-Host ''
    Write-Host 'Environment is NOT ready for a reliable Windows build.' -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host 'Environment looks ready for an unsigned Windows local build.' -ForegroundColor Green
exit 0
