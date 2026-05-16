param(
    [ValidateSet('x64', 'arm64')]
    [string]$Arch = 'x64',

    [switch]$SkipInstall,
    [switch]$SkipBuild,
    [switch]$SkipPrepackage
)

$ErrorActionPreference = 'Stop'

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Command
    )

    Write-Host ''
    Write-Host "==> $Name" -ForegroundColor Cyan
    & $Command
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

$env:ARCH = $Arch
if (-not $env:GYP_MSVS_VERSION) {
    $env:GYP_MSVS_VERSION = '2022'
}
if (-not $env:npm_config_msvs_version) {
    $env:npm_config_msvs_version = '2022'
}

Write-Host "Tabby Windows portable build" -ForegroundColor White
Write-Host "Repository: $repoRoot" -ForegroundColor White
Write-Host "Target arch: $env:ARCH" -ForegroundColor White
Write-Host "MSVS version: $env:GYP_MSVS_VERSION" -ForegroundColor White

if (-not (Test-Path 'package.json')) {
    throw 'package.json not found. Run this script from the repository root or scripts directory.'
}

if (-not (Get-Command yarn -ErrorAction SilentlyContinue)) {
    throw 'Yarn was not found in PATH. Install it with: npm i -g yarn'
}

if (-not $SkipInstall) {
    Invoke-Step 'Install dependencies' {
        yarn --network-timeout 1000000 --arch=$env:ARCH --target-arch=$env:ARCH
    }
}

if (-not $SkipBuild) {
    Invoke-Step 'Build app and packages' {
        yarn run build --arch=$env:ARCH --target_arch=$env:ARCH
    }
}

if (-not $SkipPrepackage) {
    Invoke-Step 'Prepackage builtin plugins' {
        node scripts/prepackage-plugins.mjs
    }
}

Invoke-Step 'Build Windows portable zip' {
    node scripts/build-windows-portable.mjs
}

$portable = Get-ChildItem -Path 'dist' -Filter "tabby-*-portable-$Arch.zip" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

Write-Host ''
if ($portable) {
    Write-Host "Portable build created:" -ForegroundColor Green
    Write-Host "  $($portable.FullName)" -ForegroundColor Green
} else {
    Write-Warning "Build finished, but no dist/tabby-*-portable-$Arch.zip file was found."
}
