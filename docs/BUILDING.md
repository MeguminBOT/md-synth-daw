# Building from source

Everything runs through one command, `./mdd` on a shell and `mdd.bat` on Windows. There is no
haxelib to install and nothing is put on your system: the command runs `tools/src/Run.hx` through
`haxe --run` from the repository root.

## Prerequisites

- [Haxe](https://haxe.org) 4.3 or newer
- [hxcpp](https://github.com/HaxeFoundation/hxcpp), do NOT use the old 4.3.2 version.
  ```sh
  haxelib git hxcpp https://github.com/HaxeFoundation/hxcpp.git v4.3.168
  ```

  Then build its command-line tool once, by running `haxe compile.hxml` inside `tools/hxcpp` in the
  checkout. A git checkout does not include that tool, and hxcpp stops to ask for it the first time a
  build runs.

- `git` and `curl`
- A C++ toolchain, see below

## First build

```sh
git clone https://github.com/MeguminBOT/md-synth-daw.git
cd md-synth-daw
./mdd setup     # SDL3, miniaudio, stb, the codecs and the typefaces into vendor/
./mdd run       # build it and start it
```

`mdd setup` fetches everything into `vendor/`, which is gitignored and never edited in place. If a
fetch fails, `mdd check` tells you what is present and what is missing.

## The commands

```sh
./mdd setup              # fetch the vendored sources
./mdd check              # what is present and what is missing
./mdd build              # the application, into export/bin
./mdd build gate         # the checks
./mdd build -debug       # either of them, carrying debug information
./mdd run                # build and start
./mdd gate               # every check, in order. Nonzero on any failure
./mdd gate --list        # the program names it answers to
./mdd gate window        # one check on its own
./mdd package            # a portable archive and an installer for this platform
./mdd package portable   # just the archive
./mdd notes v0.1.0       # the release notes for a tag, into export/NOTES.md
./mdd display            # write the editor's completion files again
./mdd clean              # delete export/
```

## Toolchains

A build picks its compiler, preferring LLVM wherever LLVM is installed. Pass a name to override it.

| Platform | Names |
| --- | --- |
| Windows | `msvc`, `clang-cl`, `mingw` |
| Linux, macOS | `clang`, `gcc` |

```sh
./mdd build --msvc
./mdd build --clang-cl
./mdd build --mingw
```

`llvm` is accepted as a name too, and resolves to whichever of clang-cl, clang or mingw is in hand.
A toolchain name is never a target: `if="mingw"` on a link says how a library is named to the mingw
linker, not that there is a separate mingw build to produce.

A Debian image under `tools/docker` builds the Linux one and carries the whole toolchain.

## Architecture

A build reads the machine it is running on and defines `HXCPP_M64` on x86-64 or `HXCPP_ARM64` on
arm64. `if="x86_64"` and `if="arm64"` gate an element in `mdd.xml` the same way a platform does.

Pass `--x86_64` or `--arm64` to say which, or set `MDD_ARCH`. There is no 32-bit build.

Arm64 is built by the workflows and has not been run on hardware yet, so treat a first arm64 build
as unproven until `mdd gate` has passed on one.

## Continuous integration

Two workflows under `.github/workflows`, both started by hand from the Actions tab.

| Workflow | What it does |
| --- | --- |
| `build.yml` | Builds all five targets, optionally runs the gate and builds with debug information, and keeps each package as an artifact for a fortnight |
| `release.yml` | The same five, then publishes a GitHub release from the results. It refuses to run for anybody but the repository owner, and it refuses a tag that is not the version in `mdd.xml` |

`release.yml` does not run the gate. A release build is the same source `build.yml` gates on
demand, and running twenty eight checks on five runners again buys nothing that the test workflow has
not already bought.

The release body is written by `./mdd notes`, which reads the commit log since the previous `v*`
tag, groups the subjects by the `[Category]` prefix they carry, and writes the downloads table and
the verification commands above it. It runs in a job of its own while the platforms build, and it
refuses a tag whose version is not the one in `mdd.xml`, because the built file names carry that
version and a release that disagrees with them is worse than no release. The same command run
locally writes the same file, so the notes can be read before anything is published.

`release.yml` takes a `dry_run` input. With it on, every job runs the whole way through: all five
targets build, the notes are written, the checksums are written and every file is signed and
attested. It then stops short of creating the release and the tag, and keeps the signed files as an
artifact for a week instead, with a run summary listing what a real run would have published. It is
the only way to rehearse the signing path, because keyless signing needs an OIDC token that only
GitHub can mint, and nothing running locally can stand in for it.

A dry run signs for real, so it leaves a real Rekor transparency log entry and a real provenance
attestation for files that were never released. Both are harmless and both are public.

Release files are signed with Sigstore keylessly, through the workflow's OIDC token, so no signing
key exists to be stored or leaked. Each one gets a `.sigstore` bundle beside it and a build
provenance attestation, and a `SHA256SUMS` file goes out with them. That is why `release.yml` asks
for `id-token: write` and `attestations: write` on top of `contents: write`, and why `build.yml`
asks for none of them: a test build is not signed.

The five targets are Windows x86-64, Linux x86-64, Linux arm64, macOS x86-64 and macOS arm64.

Where Haxe comes from differs by target, and the reason is arm64. The official Haxe archives are
x86-64 only, so `krdlab/setup-haxe` answers `arm64 not supported` on an arm64 runner and the job
stops before it starts. Only Windows uses that action. The Linux jobs run inside `debian:trixie` and
take `haxe`, `neko` and `libsdl3-dev` from apt, which Debian builds for both architectures, and that
is the reason those jobs use a container at all rather than the runner image. macOS takes `haxe` and
`sdl3` from Homebrew, which has arm64 bottles. Windows fetches SDL3 through `mdd setup`.

A package manager does not arrange `haxelib` the way the action does, so those jobs run
`haxelib setup` themselves.

hxcpp comes from git rather than from haxelib, at whatever the newest tag is when the job runs:
`git ls-remote --sort=-v:refname` picks it and `haxelib git` installs it. A checkout carries
`run.n`, which only launches the build tool `hxcpp.n`, and `hxcpp.n` is compiled from `tools/hxcpp`
rather than committed, so the job builds it with `haxe compile.hxml`. Left out, hxcpp stops to ask on
the terminal whether to build it, and a runner has nobody to answer. The tag is not pinned: a pin
goes stale silently, and what it would guard against is a compiler warning rather than a broken
build.

Two things a runner does not give you, both found by running the Linux job in a Debian container
rather than by reading the workflow:

- **A display.** Seven gate programs open a real window, and without one SDL answers `No available
  video device`: `window`, `paint` and `ui` stop, and `spine` and `fuzz` fail. The Linux jobs
  install `xvfb` and `xauth`, both of them, because `xvfb-run` shells out to `xauth` and Debian's
  `xvfb` package does not pull it in. macOS and Windows runners have a window server already.
- **The reference FM core.** `mdd setup` leaves Nuked-OPN2 alone unless asked, so `mdd gate chip`
  reported `not run` and the workflow went green without ever measuring the FM core against
  anything. Every job runs `mdd setup --nuked`. It is built as a program of its own and never
  shipped, so fetching it costs nothing but the megabyte.

`vgm` and `xgm` read a corpus of VGM recordings out of `vendor/vgm`, which no runner has and none
can be given, so both report `not run` and the gate passes without them. Anything that needs data
this repository cannot carry returns `Gate.SKIPPED` rather than failing, the way `chip` does when
the reference is missing: the summary names it, so a check that did not run is visible rather than
silent.

With those in place a Debian container runs the whole thing, `gate passed, vgm and xgm not run`,
and packages a 30 MB `mdd-0.1.0-linux-portable.tar.gz`.

**What macOS a package reaches back to is set by Homebrew, not by the build.** hxcpp aims at macOS
10.9 unless told otherwise, and clang raises that to 11.0 on arm64 because nothing older runs there,
but `brew` builds its bottles for the runner's own macOS. The 0.3.0 arm64 package says it needs
macOS 11.0 and carries an SDL3 built for 26.0, which will not load on anything older, and the
x86-64 one says 10.9 and carries an SDL3 built for 14.0. The macOS jobs therefore read the runner's
version and aim at it, so the binary says what it can actually do. Both macOS jobs run on macOS 26,
which for Intel is the last release there is.

## The build file

There is no `.hxml` anywhere, and none is written by hand. Every option lives in `mdd.xml`: window
size, targets, defines, vendored sources, native sources, include paths and what each platform links
against. `if="windows"`, `if="linux"`, `if="mac"`, `if="debug"` and `unless="..."` gate any element.

The build generates `mdd.Config` from the window and meta attributes, the hxcpp `native.xml` from the
native, include and link elements, and the editor's completion files, one per target. None of those
is tracked and none is written by hand.

Two elements put a shared library beside the binary, and which one applies depends on where the
library came from. `<ship>` copies a file the repository already has, which is how Windows gets the
vendored `SDL3.dll`. `<carry>` names a library linked from the system, and the build finds the copy
the binary actually links, puts it in `export/bin`, and points the binary at it: on macOS by
rewriting the load command, and on Linux by the rpath of `$ORIGIN` in the build file. Without it a
macOS build names `/opt/homebrew` or `/usr/local` and a Linux one names nothing at all, and the
archive will not start anywhere the library is not already installed at that exact path.

The build file is deliberately not called `project.xml`. A file at the repository root with that
name, or `Project.xml`, `project.hxp` or `project.lime`, makes the Lime editor extension claim the
workspace and answer the Haxe language server with the output of a `lime` command that is not
installed here, leaving the editor with no completion at all and nothing saying why.

## Adding a check

The gate's programs live in `test/`, which only the `gate` target adds to its source path, so the
application binary cannot reach them. Everything the gate runs is one binary: `mdd.gate.Gate`
dispatches on its first argument to the `run(args)` each check exposes. Adding a program means
adding `run(args)` and a case in `Gate`, and nothing else.

`mdd gate` exits nonzero on any failure and is the only claim of working that counts. Every check
from the render path onward has an offline half, because a host being right is not the same as an
engine being right, and the only way to tell them apart is to render with no host anywhere near it.

A check that cannot run for want of something the repository does not carry returns `Gate.SKIPPED`,
which is 2. The gate names it in the summary and does not count it as a failure. Returning 1 for
missing data instead means nobody without that data can pass the gate, which is what `vgm` and `xgm`
used to do.

Eight programs answer to `mdd gate` without being part of it. They are outside `PROGRAMS`, so a run
of the gate never reaches them, because each either stops the process on purpose, writes a file into
the repository, or takes long enough that nobody would sit through it on every run.

| program | what it does |
| --- | --- |
| `mdd gate fault read \| write \| overflow \| thread` | stops the process on purpose, so the crash handler can be read back from `export/fault.txt` |
| `mdd gate shot <file>` | draws the whole interface into a PNG. `--renderer <name>` draws it through one SDL backend and `--frames <n>` presents that many first, which is how two backends are compared against each other |
| `mdd gate lift` | reads a preset bank out of a folder of recordings, with hand written tables of zone names |
| `mdd gate gather <folder> <name> <file>` | the same without the tables: it works a name out from the envelope a patch carries and the pitch it was played at |
| `mdd gate kit <file>` | writes the drum kit, every hit of it arithmetic rather than a recording |
| `mdd gate convert <folder> <file> [rate]` | turns a folder of recordings into a bank, working each hit's key out from the sound |
| `mdd gate drift` | measures how far a converter run drifts from the rate it was written at |
| `mdd gate pulse` | measures where a recording's beat falls |
| `mdd gate swap` | reads what each renderer backend hands a frame to draw into, which is how deep its swapchain is |

A program that writes an asset is kept out of the gate on purpose. An asset that rewrote itself on
every run would show up as churn in a history that should only move when somebody decided something.

## Editor setup

`.vscode/settings.json` points the Haxe language server at the generated completion files and picks
between them by the file being edited: `src`, and the Haxe the build generates into `export/haxe`,
is the application, `test` is the gate, `tools` is the build command. The gate's file adds `test`
to the application's sources, so a check still completes everything in `src`. A task regenerates
the files when the folder opens, `mdd build` writes them again, and `mdd display` does it by hand.

A completion file carries every option a build does except the ones that only change generated
code: dead code elimination and the analyzer's optimisations. The language server never generates
anything, so those only cost it time, and leaving them out is where the time goes. Diagnostics are
reported for `src`, `test` and `tools`, and not for the generated Haxe or the standard library.

The same command writes `export/compile_commands.json` for C and C++: one entry for every native
source, with the include paths, defines and per-tree flags `mdd.xml` gives it, and the compiler the
chosen toolchain uses. The C/C++ extension reads it through `.vscode/settings.json`, and clangd
through `.clangd` at the repository root. The hxcpp output in `export/obj` and the vendored trees
are kept out of the C/C++ extension's symbol index, which would otherwise parse thousands of
generated files for workspace symbols. A header included from them still resolves.
