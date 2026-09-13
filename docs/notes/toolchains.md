# Toolchain notes

What compiles this, how the build chooses, and what each choice costs. `mdd.xml` declares the
choices and `tools/src/Run.hx` acts on them.

## How one is chosen

The `<toolchains>` block is in preference order. The first whose `probe` is found on the path is
what a build uses, so LLVM wins wherever LLVM is installed. A toolchain with no probe is assumed
present, which is how the Microsoft compiler is treated: hxcpp finds `cl.exe` through its own vcvars
setup rather than through the path, so probing for it would answer wrongly.

A name given to `mdd build` overrides the choice. A name is also a build condition, so `if="mingw"`
and `unless="msvc"` gate any element, and `if="llvm"` holds for clang-cl, clang and mingw alike.

`mdd check` prints the list with the chosen one marked.

## Windows

hxcpp 4.3.0 hard-codes `exe="cl.exe"` in `msvc-toolchain.xml` with no override, which reads like
clang-cl is impossible. It is not. `BuildTool.hx:222-226` includes `HXCPP_CONFIG` **after** the
toolchain file and parses its `exes` section, and a `<compiler id="MSVC" exe="clang-cl.exe">` there
merges over the earlier definition. `setup/hxcpp-clang-cl.xml` in FNF-PsychEngine is the working
reference this was taken from.

Two details from that reference are worth keeping:

- A `<linker>` cannot change an already-set `exe` attribute. It needs an `<exe>` child to force it.
- clang-cl warns about cl-style flags it accepts but ignores, so the generated config carries the
  eleven `-Wno-` flags that keep a build readable.

**Nothing depends on a hand-edited `~/.hxcpp_config.xml`.** The config is generated into
`export/build/` and passed through the `HXCPP_CONFIG` environment variable, which `Setup.hx:191`
treats as authoritative and leaves alone. The generated file includes the home config first where
one exists, so a compile cache set up there is not lost.

**The linker stays MSVC by default.** `crash.cpp` reads inline frames out of the PDB through
`SymAddrIncludeInlineTrace` and `SymFromInlineContext`, and every build sets `HXCPP_DEBUG_LINK` to
get them. `link.exe` is the reference producer of that data. `lld-link` is available but opt-in
until its PDB is measured against `mdd gate fault read`. `HXCPP_FAST_LINK` is incompatible with lld
and is gated off whenever lld is selected.

### mingw

Builds, and the whole gate passes under it. **It produces no crash report**: the binary carries
DWARF rather than a PDB, so DbgHelp has nothing to read, and the unhandled exception filter does not
fire at all. `mdd gate fault read` returns having written nothing.

An earlier attempt at gating this made the handler hang for over five minutes instead of failing,
which is worse than useless. `MDD_CRASH_PDB` now decides at compile time: off, the report says why
it has no stack rather than trying to walk one.

mingw is asked for by name rather than picked up, because it is a different ABI. Its linker takes
`SDL3.dll` directly, so it needs no import library and nothing extra is fetched for it.

## What a second compiler found

Three real portability faults, none of which MSVC would ever have reported:

- **libvorbis did not compile.** `setup_44.h` quote-includes `"modes/floor_all.h"`, which resolves
  only with `lib/` on the path. MSVC finds it anyway by walking the include stack, which is a
  Microsoft extension no other compiler has.
- **Fixing that broke libopus**, because both libraries declare `mdct_lookup` and a shared include
  path lets one see the other's header. hxcpp **ignores `<compilerflag>` inside `<file>`**: only
  `depend` is read there, so a per-file flag silently does nothing. A tree that needs its own
  include gets its own file group instead, which is what `include=` on `<tree>` does.
- **`#pragma comment(lib, ...)` is invisible to everything but MSVC.** dbghelp, winmm, psapi and pdh
  are named in `mdd.xml` now, in both `.lib` and `-l` form.

Plus five `_snprintf_s` and `_snwprintf_s` calls, which are Microsoft's and are now `snprintf` and
`swprintf`.

## Sizes

Measured on the same source, same day: msvc `gate.exe` 9.25 MB, mingw 106.6 MB. The difference is
unstripped DWARF.

## Linux

Measured on Debian trixie, clang 19, SDL3 from `libsdl3-dev` and hxcpp 4.3.2.
`tools/docker/Dockerfile` is the image and carries the two commands at the bottom. It takes hxcpp
from its newest git tag, as the workflows do, so it builds on a newer hxcpp than these measurements
were taken on. The whole gate passes, including `chip` at
1032 of 1032 fixtures bit identical against a Nuked-OPN2 reference built by gcc
in the same container. The FM core produces the same bytes under clang as under MSVC.

`clang` is preferred over `gcc` by the ordering in `mdd.xml`, through the `<exe name="${CXX}">` hook
at `linux-toolchain.xml:37`.

Three faults only a second platform could have found:

- **`mdd build` produced a binary with no execute bit.** `File.copy` writes a plain file, so
  `export/bin/mdd` could not be run. `Run.hx` chmods it off Windows now.
- **A clean checkout did not build at all.** `mdd.view.editor.Presets` imported `mdd.ui.Icon`, and
  the build generates `mdd.Icon`. It only ever worked because a stale `mdd/ui/Icon.hx` from an
  earlier layout was still sitting in `export/haxe`, which no fresh clone would have. Running the
  build in a container is what a clean checkout looks like.
- **The status readout was dead.** `usage.cpp` had a stub off Windows returning -1 for everything.
  It now reads `getrusage` for cpu, `/proc/self/statm` for memory on Linux and `task_info` on
  macOS. The gpu figure stays -1: there is no portable answer, and PDH is a Windows counter.

### Half a surrogate pair is not portable

`String.fromCharCode(0xD834)` gives a lone surrogate on Windows and **U+FFFD on Linux**, because
hxcpp will not hold half a pair in a UTF-8 string. Two consequences, both found by running the gate
on Linux:

- `Presence.quoted` emitted the two halves through separate `addChar` calls, and the Linux string
  builder replaced the first before the second arrived, so an astral character reached Discord as
  two replacement marks. It takes the pair as a substring now.
- Fixtures that build a pair out of two `fromCharCode` calls test nothing off Windows. They use a
  `"\u{1D11E}"` literal, and the checks assert the invariant, that no unpaired surrogate survives,
  rather than an exact string that only one target produces.

### macOS

Written, not run. There is no Mac here. `usage.cpp` uses `task_info` with `MACH_TASK_BASIC_INFO`,
which is the standard call, and the toolchain is hxcpp's own `HXCPP_CLANG`. Treat it as untested
until somebody builds it.
