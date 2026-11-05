#Requires -Version 7.4
<#
.SYNOPSIS
Builds native Windows ARJ on Linux with MinGW-w64.

.PARAMETER Architecture
x86 (i686-w64-mingw32) or x64 (x86_64-w64-mingw32).

.PARAMETER OutputDirectory
New directory for arj.exe, rearj.exe, arjcrypt.dll and the licence notices.

.PARAMETER ReferenceDirectory
Optional new directory that receives the native Linux arj built from the same
source on the way, for archive exchange tests.
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
& (Join-Path $PSScriptRoot 'powershell/linux/all/build_windows.ps1') @PSBoundParameters
