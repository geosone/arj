#Requires -Version 7.4
<#
.SYNOPSIS
Cross-builds native Windows ARJ with MinGW-w64 on Linux.

.DESCRIPTION
ARJ's build runs its own tools while compiling: msgbind generates the message
tables, postproc stamps the integrity CRC and the build-host arj packs the
help archive that is joined to arj.exe. A full native Linux ARJ is therefore
built first from the same copy of the source, then the MinGW target, which
uses that native arj (ARJ_FOR_BUILD_PROG) instead of compiling one with the
target's configuration.

Requires Linux, make, gcc, autoconf/automake and the matching MinGW-w64 C
compiler. Both builds run in fresh private directories, so object files cannot
leak between architectures, and every output directory must be new.
SOURCE_DATE_EPOCH (help archive timestamp) defaults to the last commit time.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('x86', 'x64')]
    [string]$Architecture,

    [Parameter(Mandatory)]
    [string]$OutputDirectory,

    [string]$ReferenceDirectory = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (!$IsLinux) {
    throw 'This cross-build entry requires Linux and MinGW-w64.'
}
$triplet = if ($Architecture -eq 'x86') {
    'i686-w64-mingw32'
} else {
    'x86_64-w64-mingw32'
}
foreach ($command in @('make', 'gcc', 'autoreconf', "$triplet-gcc")) {
    $null = Get-Command $command -CommandType Application -ErrorAction Stop
}

$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) {
    throw 'OutputDirectory must be new.'
}
if ($ReferenceDirectory) {
    $ReferenceDirectory = [IO.Path]::GetFullPath($ReferenceDirectory)
    if (Test-Path -LiteralPath $ReferenceDirectory) {
        throw 'ReferenceDirectory must be new.'
    }
}

$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
if (!$env:SOURCE_DATE_EPOCH) {
    $epoch = & git -C $source log -1 --format=%ct 2>$null
    if ($LASTEXITCODE -or !$epoch) {
        throw 'Set SOURCE_DATE_EPOCH when building outside a Git checkout.'
    }
    $env:SOURCE_DATE_EPOCH = $epoch.Trim()
}

function Invoke-Build {
    <# Runs a build command in a directory; output goes to a log in the work root. #>
    param(
        [string]$Directory,
        [string]$Command,
        [string[]]$Arguments,
        [string]$Log
    )

    Push-Location $Directory
    try {
        & $Command @Arguments *> $Log
        if ($LASTEXITCODE -ne 0) {
            Get-Content -LiteralPath $Log -Tail 40 | Write-Host
            throw "$Command failed in $Directory; see the log above."
        }
    } finally {
        Pop-Location
    }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('arj-build-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work
try {
    # Build the committed HEAD, without Git metadata or earlier build outputs.
    $tree = Join-Path $work 'tree'
    $null = New-Item -ItemType Directory -Path $tree
    & git -C $source archive --format=tar HEAD | & tar -x -C $tree
    if ($LASTEXITCODE -ne 0) {
        throw 'Cannot copy the source tree.'
    }
    Invoke-Build (Join-Path $tree 'gnu') 'autoreconf' @('-fi') (Join-Path $work 'autoreconf.log')

    $native = Join-Path $work 'native'
    $cross = Join-Path $work 'cross'
    & cp -a $tree $native
    & cp -a $tree $cross
    if ($LASTEXITCODE -ne 0) {
        throw 'Cannot prepare the build directories.'
    }

    # Native Linux ARJ: message tables for UNIX and a build-host packer.
    Invoke-Build (Join-Path $native 'gnu') './configure' @() (Join-Path $work 'native-configure.log')
    Invoke-Build $native 'make' @('-j4', 'CPPFLAGS=-D_GNU_SOURCE') (Join-Path $work 'native-make.log')
    $nativeArj = Get-ChildItem -LiteralPath $native -Recurse -File -Filter 'arj' |
        Where-Object { $_.Directory.Name -eq 'arj' } |
        Select-Object -First 1
    if (!$nativeArj) {
        throw 'The native ARJ build produced no arj executable.'
    }

    # Windows target. The tools in TOOLS_DIR stay native build-host programs.
    $buildTriplet = (& (Join-Path $cross 'gnu/config.guess')).Trim()
    Invoke-Build (Join-Path $cross 'gnu') './configure' @("--host=$triplet", "--build=$buildTriplet") (Join-Path $work 'cross-configure.log')
    Invoke-Build $cross 'make' @(
        '-j4',
        'BUILD_STRIP=1',
        'CPPFLAGS_FOR_BUILD=-D_GNU_SOURCE',
        "ARJ_FOR_BUILD_PROG=$($nativeArj.FullName)",
        'ARJ_FOR_BUILD_DEP='
    ) (Join-Path $work 'cross-make.log')

    $null = New-Item -ItemType Directory -Path $OutputDirectory
    $binaries = @{
        'arj.exe'      = 'arj'
        'rearj.exe'    = 'rearj'
        'arjcrypt.dll' = 'arjcrypt'
    }
    foreach ($name in $binaries.Keys) {
        $file = Get-ChildItem -LiteralPath $cross -Recurse -File -Filter $name |
            Where-Object { $_.Directory.Name -eq $binaries[$name] } |
            Select-Object -First 1
        if (!$file) {
            throw "The Windows build produced no $name."
        }
        Copy-Item -LiteralPath $file.FullName -Destination $OutputDirectory
    }
    Copy-Item -LiteralPath (Join-Path $source 'doc/COPYING') -Destination $OutputDirectory
    Copy-Item -LiteralPath (Join-Path $source 'debian/copyright') -Destination (Join-Path $OutputDirectory 'COPYRIGHT.txt')
    Copy-Item -LiteralPath (Join-Path $source 'resource/rearj.cfg.example') -Destination $OutputDirectory
    Copy-Item -LiteralPath (Join-Path $source 'PACKAGING.md') -Destination $OutputDirectory

    if ($ReferenceDirectory) {
        $null = New-Item -ItemType Directory -Path $ReferenceDirectory
        Copy-Item -LiteralPath $nativeArj.FullName -Destination $ReferenceDirectory
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force
}
