#Requires -Version 7.4
<#
.SYNOPSIS
Packages native ARJ for per-machine Windows installation with a managed PATH entry.

.DESCRIPTION
Requires Linux, wixl and msitools. BinaryDirectory must come from
build_windows.ps1 for this architecture; SourceArchive must hold the complete
corresponding source. The MSI installs under Program Files\ARJ and appends that
folder to the machine PATH; repair keeps one member and uninstall removes only
its own. Nothing is installed on the build host.

Release N of ARJ 3.10.22 is arj-3.10.22-N-windows-<arch>.msi with MSI version
3.10.(2200+N). The upgrade code is fixed per architecture, so a newer release
replaces an older one and downgrades are refused.
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
Set-StrictMode -Version Latest

# One place for the release number: file names, MSI version and notes.
$release = 2
$version = "3.10.22-$release"
$msiVersion = '3.10.' + (2200 + $release)

if (!$IsLinux) {
    throw 'MSI packaging requires Linux and wixl.'
}
$null = Get-Command wixl -CommandType Application -ErrorAction Stop
$binary = (Resolve-Path -LiteralPath $BinaryDirectory).Path
$source = (Resolve-Path -LiteralPath $SourceArchive).Path

$profiles = @{
    x86 = @{
        Machine   = 0x14c
        Folder    = 'ProgramFilesFolder'
        Win64     = 'no'
        Upgrade   = 'b7f1c2d4-5e33-4a8f-9c61-2a0d7e4b9f10'
        Component = '3c9a6e21-8d47-4f0b-a5e2-7b1f04c8d933'
    }
    x64 = @{
        Machine   = 0x8664
        Folder    = 'ProgramFiles64Folder'
        Win64     = 'yes'
        Upgrade   = 'e2a85f17-0c6b-4d39-b8f4-61c3a9d27e45'
        Component = '9d40b7c3-2f18-4e6a-8c05-d3e7a1f6b284'
    }
}
$profile = $profiles[$Architecture]

# Check the PE machine type (COFF header after "PE\0\0" at the offset stored
# at 0x3c) of every shipped binary against the MSI target.
foreach ($name in @('arj.exe', 'rearj.exe', 'arjcrypt.dll')) {
    $bytes = [IO.File]::ReadAllBytes((Join-Path $binary $name))
    $pe = [BitConverter]::ToInt32($bytes, 0x3c)
    if ([Text.Encoding]::ASCII.GetString($bytes, $pe, 4) -ne "PE`0`0" -or
        [BitConverter]::ToUInt16($bytes, $pe + 4) -ne $profile.Machine) {
        throw "$name does not match the MSI target architecture."
    }
}

$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) {
    throw 'Choose a new output directory.'
}
$payload = Join-Path $OutputDirectory 'payload'
$null = New-Item -ItemType Directory -Path $payload
foreach ($name in @('arj.exe', 'rearj.exe', 'arjcrypt.dll', 'COPYING', 'COPYRIGHT.txt', 'rearj.cfg.example', 'PACKAGING.md')) {
    Copy-Item -LiteralPath (Join-Path $binary $name) -Destination $payload
}
Copy-Item -LiteralPath $source -Destination (Join-Path $payload 'source.tar.gz')
Copy-Item -LiteralPath '/usr/share/doc/mingw-w64-common/copyright' -Destination (Join-Path $payload 'MINGW-NOTICES.txt')
Copy-Item -LiteralPath '/usr/share/doc/gcc-mingw-w64-base/copyright' -Destination (Join-Path $payload 'GCC-NOTICES.txt')
$payloadXml = [Security.SecurityElement]::Escape($payload)

# The ARJ binaries carry no version resource, so wixl's empty File.Version
# cannot make Windows Installer keep an older file during a major upgrade.
$definition = @"
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="*" Name="ARJ $version ($Architecture)" Language="1033" Version="$msiVersion" Manufacturer="Disconnected by Peer AT" UpgradeCode="$($profile.Upgrade)">
    <Package InstallerVersion="500" Compressed="yes" InstallScope="perMachine" />
    <Media Id="1" Cabinet="arj.cab" EmbedCab="yes" />
    <MajorUpgrade DowngradeErrorMessage="A newer ARJ package is already installed." />
    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="$($profile.Folder)">
        <Directory Id="INSTALLFOLDER" Name="ARJ">
          <Component Id="Runtime" Guid="$($profile.Component)" Win64="$($profile.Win64)">
            <File Id="ArjExe" Source="$payloadXml/arj.exe" KeyPath="yes" />
            <File Id="RearjExe" Source="$payloadXml/rearj.exe" />
            <File Id="ArjcryptDll" Source="$payloadXml/arjcrypt.dll" />
            <File Id="SourceCode" Source="$payloadXml/source.tar.gz" />
            <File Id="Copying" Source="$payloadXml/COPYING" />
            <File Id="Copyright" Source="$payloadXml/COPYRIGHT.txt" />
            <File Id="RearjConfig" Source="$payloadXml/rearj.cfg.example" />
            <File Id="Packaging" Source="$payloadXml/PACKAGING.md" />
            <File Id="MingwNotice" Source="$payloadXml/MINGW-NOTICES.txt" />
            <File Id="GccNotice" Source="$payloadXml/GCC-NOTICES.txt" />
          </Component>
        </Directory>
      </Directory>
    </Directory>
    <Feature Id="Main" Title="ARJ commands, matching source, notices and system PATH entry" Level="1">
      <ComponentRef Id="Runtime" />
    </Feature>
  </Product>
</Wix>
"@
$wxs = Join-Path $OutputDirectory 'arj.wxs'
[IO.File]::WriteAllText($wxs, $definition)
$package = Join-Path $OutputDirectory "arj-$version-windows-$Architecture.msi"
& wixl -a $Architecture -o $package $wxs
if ($LASTEXITCODE -ne 0) {
    throw 'ARJ MSI packaging failed.'
}
& (Join-Path $PSScriptRoot '../../../packaging/finalize_msi_path.ps1') -Package $package -Component Runtime
[pscustomobject]@{
    Package      = $package
    Architecture = $Architecture
    SHA256       = (Get-FileHash -LiteralPath $package).Hash.ToLowerInvariant()
}
