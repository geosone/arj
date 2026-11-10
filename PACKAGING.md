# Native Windows ARJ build and qualification

This repository builds the open-source ARJ 3.10.22 (ARJ Software Russia,
GPL-2+) as native Win32 and Win64 programs with MinGW-w64.

## History

1. `Import ARJ 3.10.22 upstream source`: the unmodified
   `arj_3.10.22.orig.tar.gz`.
2. `Apply the Debian arj 3.10.22-29 packaging and patch series`: `debian/`
   from `arj_3.10.22-29.debian.tar.xz` with all 24 patches applied. They
   include the published security fixes (CVE-2015-0556, CVE-2015-0557,
   CVE-2015-2782 and the AFL/out-of-bounds fixes) and the 64-bit fixes.
   Both tarballs were checked against the SHA-256 sums in the sid `Sources`
   index, whose `InRelease` signature was verified with the Debian archive
   keyring.
3. The Windows port and the fixes below, one commit per topic.

[joncampbell123/arj](https://github.com/joncampbell123/arj) (last changed in
2016) was compared with this tree. Its overlapping-`strcpy` and pointer-width
fixes are covered by Debian (`006_use_safe_strcpy`, `003_64_bit_clean`). Its
32-bit CRC/ARJ-SECURITY types were adopted; its DOS assembly removal,
`/usr/share/doc` help lookup and build scripts were not.

## Changes over Debian

- MinGW-w64 host support in `gnu/configure.in` and `gnu/makefile.in`. A cross
  build keeps the build-host tools (msgbind, postproc, join, packager) native.
- Small portability fixes for MinGW-w64 and GCC 14 (`ntstream.h`, `environ.c`,
  `environ.h`, `ea_mgr.c`, `msgbind.c`). The 32-bit `time_t` localtime
  workaround stays limited to Win32 without `_WIN64`.
- Extraction refuses member names that would leave the target directory. The
  Debian traversal patch strips a leading `../` or separator, but a name such
  as `a/../../x` was still written one level above the target by `arj x`,
  each further `..` one more (reproduced with Debian's arj 3.10.22-28 and
  -29; reported as [Debian bug #1153489](https://bugs.debian.org/1153489),
  where the generic part of this fix is attached). On Windows, names containing
  drive or stream colons, reserved characters, control characters, components
  ending in a dot or space, or device names (`CON`, `NUL`, `COM1`, ...) are
  refused too. A refused member is reported as skipped and counts as an error.
- The SFX modules' `file_chdir()` allocates the terminating NUL.
- CRC-32 and ARJ-SECURITY state use `uint32_t` (see above).

## Build

On Linux with make, gcc, autoconf, automake, MinGW-w64 and PowerShell 7.4:

```powershell
./build_windows.ps1 -Architecture x86 -OutputDirectory /tmp/arj-win32 -ReferenceDirectory /tmp/arj-linux
./build_windows.ps1 -Architecture x64 -OutputDirectory /tmp/arj-win64
```

The script builds the committed `HEAD` in a new temporary directory: first a
native Linux ARJ (ARJ packs its own help archive during the build), then the
MinGW target. `SOURCE_DATE_EPOCH` defaults to the last commit time, which
makes the embedded help archive reproducible.

`new_windows_msi.ps1` packages a build with its matching source:

```powershell
git archive --format=tar.gz -o /tmp/arj-win64/source.tar.gz HEAD
./new_windows_msi.ps1 -BinaryDirectory /tmp/arj-win64 -SourceArchive /tmp/arj-win64/source.tar.gz -OutputDirectory /tmp/arj-msi64 -Architecture x64
```

Release N is `arj-3.10.22-N-windows-<arch>.msi` with MSI version
`3.10.(2200+N)`. The MSI installs under `Program Files\ARJ` and appends that
directory to the machine PATH through the MSI Environment table
(`packaging/finalize_msi_path.ps1`). Repair keeps one member; uninstall
removes only its own. Restart shells and services afterwards.

## Tests

`packaging/test_roundtrip.ps1` archives a fixture tree (CRLF text, all byte
values including 0x1A, compressible text, an empty and a nested file, in a
directory with a space) with methods 0 to 4, tests it and extracts it with
and without paths. It also runs the Mystic archive record forms:

```text
pack    arj a -e -y "%1" "%2"
unpack  arj e -y "-ht%3" "%1" "%2"
```

ARJ only accepts a switch value attached to the switch: `-w "%3"` fails with
"Missing filename argument for -w".

`-ReferenceArchive` extracts an archive from the other platform's build;
`-CheckUnsafeNames` rewrites a valid member header and checks the refusals.
`packaging/test_windows_msi.ps1` covers MSI install, repair, PATH discovery
from CMD and PowerShell and exact PATH restoration on uninstall.

Native Windows 10 x86 and x64, Linux, and Debian arj 3.10.22-28 interop tests
passed on 2026-11-05.

## Releases

- 3.10.22-1 (2026-11-05): binary-only MSIs on bbs.disconnected-by-peer.at,
  published while the traversal report was private; never a GitHub release.
- 3.10.22-2: first public release with matching source, built by CI from
  this repository. -1 was packaged by an unpublished variant of
  `new_windows_msi.ps1` and cannot be rebuilt from here, so the version was
  not reused.

## Limits

Unicode file names are not qualified. Multi-volume archives,
SFX creation, GOST encryption and ARJ-SECURITY envelopes compile but are not
covered by the tests. This is not a complete audit of the legacy parser.

## Licence

GPL-2+, see `doc/COPYING` and `debian/copyright`. Distribute binaries only
together with their corresponding source; the MSI and the release include it.
