#Requires -Version 7.4
<#
.SYNOPSIS
Packages a qualified native ARJ build, matching source and a system PATH entry.

.PARAMETER BinaryDirectory
Output of build_windows.ps1 for the same architecture.

.PARAMETER SourceArchive
Complete corresponding source (git archive of the release commit).

.PARAMETER OutputDirectory
New directory for the MSI and its intermediate files.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$BinaryDirectory,

    [Parameter(Mandatory)]
    [string]$SourceArchive,

    [Parameter(Mandatory)]
    [string]$OutputDirectory,

    [Parameter(Mandatory)]
    [ValidateSet('x86', 'x64')]
    [string]$Architecture
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'powershell/linux/all/new_windows_msi.ps1') @PSBoundParameters
