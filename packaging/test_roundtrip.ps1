#Requires -Version 7.4
<#
.SYNOPSIS
Qualifies an ARJ executable with deterministic round trips and unsafe names.

.DESCRIPTION
Creates a fixture tree (FILE_ID.DIZ with CRLF, every byte value including
0x1A, compressible text, an empty file and a nested file) in a directory whose
name contains a space. For methods 0 to 4 it archives the tree with paths,
tests the archive, extracts it with "x" and "e" and compares every file. It
also runs the command forms used for Mystic archive records:
pack   arj a -e -y "%1" "%2"
unpack arj e -y "-ht%3" "%1" "%2"

ReferenceArchive is an archive made by a different build (Linux/Windows) from
the same fixture; it must extract to identical bytes.

CheckUnsafeNames rewrites the stored member name of a one-file archive and
requires that crafted names never produce a file outside the target directory.
"a/../../x" must be refused on every platform. On Windows, names that address
devices or alternate data streams or that end in a dot or space are refused
too. A leading "../" or "/" is stripped by ARJ itself and must stay inside.

.PARAMETER WorkDirectory
New directory that keeps the results (method 4 archive: trial.arj).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ArjPath,

    [string]$WorkDirectory = '',

    [string]$ReferenceArchive = '',

    [switch]$CheckUnsafeNames
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$arj = (Resolve-Path -LiteralPath $ArjPath).Path
if ($WorkDirectory) {
    $work = [IO.Path]::GetFullPath($WorkDirectory)
    if (Test-Path -LiteralPath $work) {
        throw 'WorkDirectory must be new.'
    }
} else {
    $work = Join-Path ([IO.Path]::GetTempPath()) ('arj-test-' + [guid]::NewGuid().ToString('N'))
}
$null = New-Item -ItemType Directory -Path $work

function Invoke-Arj {
    <# Runs ARJ; returns its exit code. Output is kept in arj.log. #>
    param(
        [string[]]$Arguments,
        [string]$Directory = $work
    )

    Push-Location -LiteralPath $Directory
    try {
        & $arj @Arguments *>> (Join-Path $work 'arj.log')
        return $LASTEXITCODE
    } finally {
        Pop-Location
    }
}

function Assert-Arj {
    param(
        [string[]]$Arguments,
        [string]$Directory = $work
    )

    $code = Invoke-Arj $Arguments $Directory
    if ($code -ne 0) {
        throw "arj $($Arguments -join ' ') returned $code; see $work/arj.log."
    }
}

function New-Fixture {
    <# Writes the deterministic fixture tree. #>
    param(
        [string]$Directory
    )

    $null = New-Item -ItemType Directory -Path (Join-Path $Directory 'sub')
    [IO.File]::WriteAllText((Join-Path $Directory 'FILE_ID.DIZ'), "ARJ qualification`r`nline two`r`n")
    $all = [byte[]]::new(256 * 64)
    for ($i = 0; $i -lt $all.Length; $i++) {
        $all[$i] = [byte]($i % 256)
    }
    [IO.File]::WriteAllBytes((Join-Path $Directory 'allbytes.bin'), $all)
    [IO.File]::WriteAllText((Join-Path $Directory 'text.txt'), ('The quick brown fox jumps over the lazy dog. ' * 2000))
    [IO.File]::WriteAllBytes((Join-Path $Directory 'empty.dat'), [byte[]]::new(0))
    [IO.File]::WriteAllText((Join-Path $Directory 'sub/nested.txt'), "nested member`n")
}

function Assert-SameTree {
    <# Every fixture file must exist below Actual with identical bytes. #>
    param(
        [string]$Expected,
        [string]$Actual,
        [switch]$Flat
    )

    foreach ($file in Get-ChildItem -LiteralPath $Expected -Recurse -File) {
        $relative = [IO.Path]::GetRelativePath($Expected, $file.FullName)
        if ($Flat) {
            $relative = $file.Name
        }
        $candidate = Join-Path $Actual $relative
        if (!(Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Missing extracted member: $relative"
        }
        if ((Get-FileHash -LiteralPath $candidate).Hash -ne (Get-FileHash -LiteralPath $file.FullName).Hash) {
            throw "Extracted member differs: $relative"
        }
    }
}

$fixture = Join-Path $work 'fixture dir'
New-Fixture $fixture

# Round trips with every compression method, keeping paths ("x") and not ("e").
# Members are named explicitly: PowerShell on Unix expands '*' itself, and ARJ
# reads a leading existing directory name as a base directory.
$members = @(Get-ChildItem -LiteralPath $fixture -Recurse -File |
        ForEach-Object { [IO.Path]::GetRelativePath($fixture, $_.FullName) } |
        Sort-Object)
foreach ($method in 0..4) {
    $archive = Join-Path $work "trial$method.arj"
    Assert-Arj (@('a', '-y', "-m$method", $archive) + $members) $fixture
    Assert-Arj @('t', '-y', $archive)
    $out = Join-Path $work "x out $method"
    $null = New-Item -ItemType Directory -Path $out
    Assert-Arj @('x', '-y', "-ht$out", $archive)
    Assert-SameTree $fixture $out
    $flat = Join-Path $work "e out $method"
    $null = New-Item -ItemType Directory -Path $flat
    Assert-Arj @('e', '-y', "-ht$flat", $archive)
    Assert-SameTree $fixture $flat -Flat
}
Copy-Item -LiteralPath (Join-Path $work 'trial4.arj') -Destination (Join-Path $work 'trial.arj')
'PASS ARJ methods 0-4: add, test, extract with and without paths'

# Mystic archive record command forms (%1 archive, %2 file, %3 directory).
$mysticArchive = Join-Path $work 'mystic upload.arj'
Assert-Arj @('a', '-e', '-y', $mysticArchive, (Join-Path $fixture 'FILE_ID.DIZ'))
$mysticOut = Join-Path $work 'mystic temp'
$null = New-Item -ItemType Directory -Path $mysticOut
Assert-Arj @('e', '-y', "-ht$mysticOut", $mysticArchive, 'FILE_ID.DIZ')
if ((Get-FileHash -LiteralPath (Join-Path $mysticOut 'FILE_ID.DIZ')).Hash -ne
    (Get-FileHash -LiteralPath (Join-Path $fixture 'FILE_ID.DIZ')).Hash) {
    throw 'Mystic-style FILE_ID.DIZ extraction differs.'
}
'PASS Mystic record command forms (pack -e, unpack -ht)'

if ($ReferenceArchive) {
    $reference = (Resolve-Path -LiteralPath $ReferenceArchive).Path
    $out = Join-Path $work 'reference out'
    $null = New-Item -ItemType Directory -Path $out
    Assert-Arj @('t', '-y', $reference)
    Assert-Arj @('x', '-y', "-ht$out", $reference)
    Assert-SameTree $fixture $out
    'PASS archive from the other build extracts to identical bytes'
}

if ($CheckUnsafeNames) {
    # CRC-32 (IEEE, reflected 0xEDB88320) as used by ARJ header checks.
    $table = [uint32[]]::new(256)
    for ($n = 0; $n -lt 256; $n++) {
        $c = [uint32]$n
        for ($k = 0; $k -lt 8; $k++) {
            if ($c -band 1) {
                $c = [uint32](0xEDB88320u -bxor ($c -shr 1))
            } else {
                $c = [uint32]($c -shr 1)
            }
        }
        $table[$n] = $c
    }

    function Get-Crc32 {
        param(
            [byte[]]$Data
        )

        $crc = 0xFFFFFFFFu
        foreach ($b in $Data) {
            $crc = [uint32]($table[($crc -bxor $b) -band 0xFF] -bxor ($crc -shr 8))
        }
        return [uint32]($crc -bxor 0xFFFFFFFFu)
    }

    function Get-HeaderEnd {
        <# Returns the offset after a header and its extended headers. #>
        param(
            [byte[]]$Data,
            [int]$Position
        )

        if ($Data[$Position] -ne 0x60 -or $Data[$Position + 1] -ne 0xEA) {
            throw 'Missing ARJ header id.'
        }
        $size = [BitConverter]::ToUInt16($Data, $Position + 2)
        $next = $Position + 8 + $size
        while ($true) {
            $extended = [BitConverter]::ToUInt16($Data, $next)
            $next += 2
            if ($extended -eq 0) {
                return $next
            }
            $next += $extended + 4
        }
    }

    function New-RenamedArchive {
        <#
        Rewrites the first member's stored name. ARJ header layout as read by
        arj_arcv.c read_header(): 0x60 0xEA, basic header size (LE word), basic
        header, CRC-32 of the basic header, extended headers. In the basic
        header byte 0 is first_hdr_size, byte 4 arj_flags (0x10 PATHSYM_FLAG:
        '/' separators), bytes 24-25 entry_pos (start of the name part); the
        NUL-terminated name starts at first_hdr_size, then the comment.
        #>
        param(
            [string]$Source,
            [string]$Target,
            [string]$Name
        )

        $data = [IO.File]::ReadAllBytes($Source)
        $member = Get-HeaderEnd $data 0
        $size = [BitConverter]::ToUInt16($data, $member + 2)
        $basic = $data[($member + 4)..($member + 3 + $size)]
        $first = $basic[0]
        $nameEnd = [Array]::IndexOf($basic, [byte]0, $first)
        $commentEnd = [Array]::IndexOf($basic, [byte]0, $nameEnd + 1)
        $fixed = [byte[]]$basic[0..($first - 1)]
        $fixed[4] = $fixed[4] -bor 0x10
        $entry = $Name.LastIndexOf('/') + 1
        $fixed[24] = [byte]($entry -band 0xFF)
        $fixed[25] = [byte]($entry -shr 8)
        $nameBytes = [Text.Encoding]::Latin1.GetBytes($Name)
        $comment = [byte[]]$basic[($nameEnd + 1)..$commentEnd]
        $new = [byte[]]($fixed + $nameBytes + [byte[]]@(0) + $comment)
        $crc = Get-Crc32 $new
        $out = [Collections.Generic.List[byte]]::new()
        $out.AddRange([byte[]]$data[0..($member - 1)])
        $out.AddRange([byte[]]@(0x60, 0xEA))
        $out.AddRange([BitConverter]::GetBytes([uint16]$new.Length))
        $out.AddRange($new)
        $out.AddRange([BitConverter]::GetBytes($crc))
        $out.AddRange([byte[]]$data[($member + 8 + $size)..($data.Length - 1)])
        [IO.File]::WriteAllBytes($Target, $out.ToArray())
    }

    $baseDirectory = Join-Path $work 'unsafe base'
    $null = New-Item -ItemType Directory -Path $baseDirectory
    [IO.File]::WriteAllText((Join-Path $baseDirectory 'payload.txt'), 'PAYLOAD')
    $base = Join-Path $work 'unsafe-base.arj'
    Assert-Arj @('a', '-y', $base, 'payload.txt') $baseDirectory

    $refused = @('a/../../evil.txt', 'a/b/../../../evil.txt', 'a/./../../evil.txt')
    if ($IsWindows) {
        $refused += @('a/CON', 'a/con.txt', 'a/NUL .txt', 'a/COM1.txt', 'a/evil.txt:stream', 'a/evil.', 'a/evil ', 'a/ev|il.txt')
    }
    $index = 0
    foreach ($name in $refused) {
        $index++
        $crafted = Join-Path $work "unsafe$index.arj"
        New-RenamedArchive $base $crafted $name
        $sandbox = Join-Path $work "sandbox $index"
        $target = Join-Path $sandbox 'one/two/out'
        $null = New-Item -ItemType Directory -Path $target
        $code = Invoke-Arj @('x', '-y', "-ht$target", $crafted)
        $written = @(Get-ChildItem -LiteralPath $sandbox -Recurse -File)
        if ($code -eq 0 -or $written.Count -ne 0) {
            throw "Unsafe member name was not refused: $name"
        }
    }
    "PASS $($refused.Count) unsafe member names refused before writing"

    # ARJ strips a leading "../" or "/"; the result must stay inside.
    foreach ($name in @('../inside.txt', '/inside.txt')) {
        $index++
        $crafted = Join-Path $work "unsafe$index.arj"
        New-RenamedArchive $base $crafted $name
        $sandbox = Join-Path $work "sandbox $index"
        $target = Join-Path $sandbox 'one/two/out'
        $null = New-Item -ItemType Directory -Path $target
        $null = Invoke-Arj @('x', '-y', "-ht$target", $crafted)
        $outside = @(Get-ChildItem -LiteralPath $sandbox -Recurse -File |
                Where-Object { !$_.FullName.StartsWith($target + [IO.Path]::DirectorySeparatorChar) })
        if ($outside.Count -ne 0) {
            throw "Leading traversal left the target directory: $name"
        }
    }
    'PASS leading ../ and / stay inside the target directory'
}

if (!$WorkDirectory) {
    Remove-Item -LiteralPath $work -Recurse -Force
}
