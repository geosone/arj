Native Windows x86/x64 builds of ARJ 3.10.22 (open-source ARJ, Debian 3.10.22-29 patch level) for BBS file areas.

The MSI installs arj.exe, rearj.exe and arjcrypt.dll under Program Files\ARJ and appends that directory to the system PATH. Repair does not duplicate the entry; uninstall removes only its own member. Restart existing shells and BBS services so they inherit the new PATH. Extracting the portable ZIP does not change PATH.

Changes over Debian: MinGW-w64 Win32/Win64 port; extraction refuses member names that leave the target directory ("a/../../x" escaped with Debian's arj 3.10.22-28/-29, Debian bug #1153489) and, on Windows, device names, drive/stream colons, reserved characters and names ending in a dot or space; CRC-32 and ARJ-SECURITY state kept at 32 bits (after joncampbell123/arj).

Includes the complete corresponding source and the GPL-2 notices. Required CI tests cover methods 0-4, extraction with and without paths, the Mystic pack/unpack command forms, Linux/Windows archive exchange, unsafe member names, and MSI install/repair/uninstall with discovery from CMD and PowerShell. Native Windows 10 x86 and x64 tests also passed.

Mystic archive record: pack `arj a -e -y "%1" "%2"`, unpack `arj e -y "-ht%3" "%1" "%2"`.
