#Requires -Version 7.4
<#
.SYNOPSIS
Tests ARJ MSI installation, repair, PATH discovery and removal on a disposable host.

.DESCRIPTION
Installs the package silently, checks that the machine PATH gained exactly one
member for Program Files\ARJ, runs the round-trip and unsafe-name tests with
the installed arj.exe, deletes arj.exe and repairs it, checks the shipped
source and notices, then uninstalls and requires the original PATH value
byte for byte. Refuses to run where an ARJ folder already exists.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Package,

    [Parameter(Mandatory)]
    [ValidateSet('x86', 'x64')]
    [string]$Architecture
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (!$IsWindows) {
    throw 'Use a disposable Windows qualification host.'
}
. (Join-Path $PSScriptRoot 'test_windows_path.ps1')

# A 32-bit package on 64-bit Windows installs below Program Files (x86).
$programs = if ($Architecture -eq 'x86' -and [Environment]::Is64BitOperatingSystem) {
    [Environment]::GetFolderPath('ProgramFilesX86')
} else {
    [Environment]::GetFolderPath('ProgramFiles')
}
$directory = Join-Path $programs 'ARJ'
$exe = Join-Path $directory 'arj.exe'
if (Test-Path -LiteralPath $directory) {
    throw 'An existing ARJ installation was preserved; use a clean host.'
}
$before = Get-TestMachinePath
$packagePath = (Resolve-Path -LiteralPath $Package).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('arj-msi-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work
$installed = $false

function Invoke-TestMsi {
    <# Runs msiexec silently with a verbose log in the work directory. #>
    param(
        [string]$Mode,
        [string]$Log
    )

    $arguments = @(
        $Mode,
        ('"' + $packagePath + '"'),
        '/qn',
        '/norestart',
        '/L*v',
        ('"' + (Join-Path $work $Log) + '"')
    )
    $process = Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -notin 0, 3010) {
        throw "Windows Installer failed ($($process.ExitCode)); inspect $work."
    }
}

try {
    Invoke-TestMsi '/i' 'install.log'
    $installed = $true
    Assert-TestToolPath -Directory $directory -Before $before
    Assert-TestToolDiscovery -Executable $exe -WorkingDirectory $work
    & (Join-Path $PSScriptRoot 'test_roundtrip.ps1') -ArjPath $exe -CheckUnsafeNames

    $hash = (Get-FileHash -LiteralPath $exe).Hash
    Remove-Item -LiteralPath $exe
    Invoke-TestMsi '/fa' 'repair.log'
    if ((Get-FileHash -LiteralPath $exe).Hash -ne $hash) {
        throw 'MSI repair did not restore the qualified executable.'
    }
    Assert-TestToolPath -Directory $directory -Before $before
    Assert-TestToolDiscovery -Executable $exe -WorkingDirectory $work

    $shipped = @(
        'rearj.exe',
        'arjcrypt.dll',
        'source.tar.gz',
        'COPYING',
        'COPYRIGHT.txt',
        'MINGW-NOTICES.txt',
        'GCC-NOTICES.txt'
    )
    foreach ($name in $shipped) {
        if (!(Test-Path -LiteralPath (Join-Path $directory $name))) {
            throw "The MSI omitted $name."
        }
    }
} finally {
    if ($installed) {
        Invoke-TestMsi '/x' 'uninstall.log'
        if (Test-Path -LiteralPath $exe) {
            throw 'Uninstall retained the executable.'
        }
        Assert-TestToolPath -Directory $directory -Before $before -Removed
    }
}
'PASS ARJ MSI install, round trip, unsafe names, repair, cmd/PowerShell discovery, exact PATH restoration and uninstall'
