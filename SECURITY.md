# Security policy

MD Synth DAW is a desktop application. It opens files people pass around, it checks for and installs
its own updates, and it talks to a few things on your own machine. A fault in any of those can be a
security problem, and this page says how to report one without putting other people at risk first.

## Supported versions

The project is in pre-release. Fixes land on `main` and go out in the next release, and only the
newest release is supported: nothing is back-ported to an older one. If you are building from
source, the supported version is the current `main`.

## What to report

Anything that lets a file, a download or another program make MD Synth DAW do something it should
not: run code, write outside the folders it owns, crash in a way someone else can trigger on
purpose, or read what it has no reason to read. The places that matter most are:

- **Files it opens.** Projects (`.mdsyn`), VGM and VGZ, XGM, MIDI, WAV and TFI files, preset bank
  JSON, and the typefaces it loads at start. All of these are parsed by code in this repository.
- **The updater.** It reads the releases page, downloads the release archive or installer, and
  replaces the program's own files with a script once the program has closed.
- **Local channels.** The Discord presence connection, the handoff that passes a file to a copy
  that is already running, and the MIDI input.
- **Crash reports**, which are written into your settings folder.

A bug in one of the vendored libraries (SDL3, miniaudio, stb_truetype, libogg, libvorbis, libopus,
libvpx or libwebm) belongs with that library's own project, unless the way MD Synth DAW calls it is
what makes it exploitable. A problem that needs an attacker to already control your account or
your machine is out of scope.

Release files are signed with Sigstore as they are built. If a download does not verify as the
[README](README.md#verifying-a-download) describes, treat it as untrusted and report where you got
it.

## How to report

**Do not open a public issue.** Use the private form instead:

1. Open the repository's **Security** tab.
2. Choose **Report a vulnerability**, or go straight to
   [the report form](https://github.com/MeguminBOT/md-synth-daw/security/advisories/new).

Only you and the maintainers can see the report. Please include:

- the version, from **Help > About**, or the commit you built;
- your operating system and whether it is the installer, the portable archive or a source build;
- the file or steps that trigger it, attached to the report rather than linked publicly;
- what happens, and the crash report from your settings folder if one was written.

## What happens next

The conversation stays in the private advisory while a fix is worked out. Once the fix is in a
release, the advisory is published so people know to update, and you are credited in it unless you
would rather not be.
