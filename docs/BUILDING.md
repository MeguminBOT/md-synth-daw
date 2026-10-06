<a id="top"></a>

# Building from source

Everything runs through one command, `./mdd` on a shell and `mdd.bat` on Windows. There is no
haxelib to install and nothing is put on your system: the command runs `tools/src/Run.hx` through
`haxe --run` from the repository root.

- [Prerequisites](#prerequisites)
- [First build](#first-build)
- [The commands](#the-commands)
- [Toolchains](#toolchains)
- [Architecture](#architecture)
- [Warnings a build prints](#warnings-a-build-prints)
- [Continuous integration](#continuous-integration)
- [The build file](#the-build-file)
- [The shipped presets](#the-shipped-presets)
- [Adding a check](#adding-a-check)
- [Editor setup](#editor-setup)

## Prerequisites

- [Haxe](https://haxe.org) 4.3 or newer
- [hxcpp](https://github.com/HaxeFoundation/hxcpp), do NOT use the old 4.3.2 version.
  ```sh
  haxelib git hxcpp https://github.com/HaxeFoundation/hxcpp.git v4.3.157
  ```

  That is the tag the `hxcpp` element in `mdd.xml` names, and the one the workflows build with. The
  tags after it carry faults in the garbage collector, and `mdd build` refuses an hxcpp that has
  one, so a newer tag stops the build rather than making a program that crashes.

  Then build its command-line tool once, by running `haxe compile.hxml` inside `tools/hxcpp` in the
  checkout. A git checkout does not include that tool, and hxcpp stops to ask for it the first time a
  build runs.

- `git` and `curl`
- A C++ toolchain, see below

<p align="right">(<a href="#top">back to top</a>)</p>

## First build

```sh
git clone https://github.com/MeguminBOT/md-synth-daw.git
cd md-synth-daw
./mdd setup     # SDL3, miniaudio, stb, the codecs and the typefaces into vendor/
./mdd run       # build it and start it
```

`mdd setup` fetches everything into `vendor/`, which is gitignored and never edited in place. If a
fetch fails, `mdd check` tells you what is present and what is missing.

<p align="right">(<a href="#top">back to top</a>)</p>

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
./mdd package            # a portable archive and an installer for this platform, and on Linux a Debian package
./mdd package portable   # just the archive
./mdd notes v0.1.0       # the release notes for a tag, into export/NOTES.md
./mdd site               # the website, into export/site
./mdd site --apt debs    # and the apt repository, from the Debian packages in debs/
./mdd display            # write the editor's completion files again
./mdd clean              # delete export/
```

**`export/bin` is laid out the way a download is.** A build puts the fonts and the icon atlases
beside the binary it makes, and the application reads them from beside itself and nowhere else,
except inside a macOS bundle, where they sit in the bundle's `Contents/Resources`. It
used to fall back to `vendor/fonts` and `export/icons` in this repository, which meant a copy with
its fonts folder missing ran perfectly here and closed on a reader's machine without a word. The
fonts beside the binary are the ones the portable archive holds, which leaves out the three a
language downloads on demand, so a copy run from here asks for those exactly as a reader's does.

**A package takes what it names and nothing else.** From beside the binary, that is the application,
the libraries `<ship>` lists and the one `<carry>` finds. Anything else that lands in `export/bin`,
such as a check program or an archive left over from something else, stays behind. The pictures the
Linux install script gives the desktop's icon theme are copied by that package alone, because
nothing else reads them: the window icon and the program's own are built into the binary.

<p align="right">(<a href="#top">back to top</a>)</p>

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

<p align="right">(<a href="#top">back to top</a>)</p>

## Architecture

A build reads the machine it is running on and defines `HXCPP_M64` on x86-64 or `HXCPP_ARM64` on
arm64. `if="x86_64"` and `if="arm64"` gate an element in `mdd.xml` the same way a platform does.

Pass `--x86_64` or `--arm64` to say which, or set `MDD_ARCH`. There is no 32-bit build.

Arm64 is built by the workflows and has not been run on hardware yet, so treat a first arm64 build
as unproven until `mdd gate` has passed on one.

<p align="right">(<a href="#top">back to top</a>)</p>

## Warnings a build prints

A clean build is not a silent one. Two warnings come out of hxcpp rather than out of this
repository, and both were measured before being left alone, by compiling the same thing twice and
comparing the bytes that came out.

**`treating 'c-header' input as 'c++-header' when in C++ mode` `[-Wdeprecated]`**, twice per clang
build. hxcpp hands clang its precompiled header without saying which language it is in, and clang
says so. Told explicitly or left to guess, clang writes the same header, and an object compiled
through either one is the same as well:

    the precompiled header   895211bf1e316670 either way
    an object through it     ab6201f1215973cd either way

Silencing it takes `-Wno-deprecated`, which would also hide real deprecation warnings in this
repository's own C++, or turning hxcpp's precompiled headers off, which makes every build slower.
Two lines of noise are cheaper than either, so it stays.

**`has C-linkage specified, but returns user-defined type 'String'` `[-Wreturn-type-c-linkage]`**,
three times per build, naming `alloc_hxs_wchar`, `alloc_hxs_utf16` and `alloc_hxs_utf8` in hxcpp's
`src/hx/CFFI.cpp`. Those three are how a loadable ndll hands strings back to Haxe, and nothing here
loads one: the words `CFFI`, `ndll` and `cpp.Lib.load` appear nowhere in `src`, `test` or `tools`.
A compile produces the same object with the warning and without it:

    the object      d309f4287e3e6ca5 either way

`vendor/` is fetched and never patched, so `mdd.xml` turns that one off with a compiler flag on
everything except MSVC, which does not know the name.

**What is not ignorable** is a warning from the linker about versions. `ld: warning: building for
macOS-11.0, but linking with dylib ... built for newer version 26.0` meant exactly what it said:
the 0.3.0 macOS packages carried an SDL3 that would not load on the macOS they claimed to support.
That one was a fault, and the macOS build now links SDL's own release, which is built for no newer
a macOS than the one the build aims at.

<p align="right">(<a href="#top">back to top</a>)</p>

## Continuous integration

Three workflows under `.github/workflows`, all started by hand from the Actions tab.

| Workflow | What it does |
| --- | --- |
| `build.yml` | Builds all five targets, optionally runs the gate and builds with debug information, and keeps each package as an artifact for a fortnight |
| `release.yml` | The same five, then publishes a GitHub release from the results. It refuses to run for anybody but the repository owner, and it refuses a tag that is not the version in `mdd.xml` |
| `pages.yml` | Writes the website with `./mdd site`, with an apt repository for the latest release's Debian packages, and publishes it to GitHub Pages. Like `release.yml`, it refuses to run for anybody but the repository owner |

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
is the reason those jobs use a container at all rather than the runner image. macOS takes `haxe`
from Homebrew, which has arm64 bottles. Windows and macOS fetch SDL3 through `mdd setup`, from
SDL's own release.

A package manager does not arrange `haxelib` the way the action does, so those jobs run
`haxelib setup` themselves.

hxcpp comes from git rather than from haxelib, at the tag the `hxcpp` element in `mdd.xml` names,
and `haxelib git` installs it. Without the element the job takes the newest tag, which
`git ls-remote --sort=-v:refname` picks. A checkout carries `run.n`, which only launches the build
tool `hxcpp.n`, and `hxcpp.n` is compiled from `tools/hxcpp` rather than committed, so the job builds
it with `haxe compile.hxml`. Left out, hxcpp stops to ask on the terminal whether to build it, and a
runner has nobody to answer.

The tag is held because the ones after it are not safe to build with. From v4.3.158 to v4.3.160 the
garbage collector frees a large object that only the stack holds, and from v4.3.161 a lock in the
collector lets two of its marking threads take the same piece of work, which crashes a collection
now and then. `mdd build` reads the collector of whichever hxcpp is installed and refuses either
fault, so moving the tag forward is safe to try: a tag that still carries one stops the build.

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
and packages the Linux portable archive.

**What macOS a package reaches back to is set in `mdd.xml`.** The `macos` element names the oldest
release, 11.0 for both architectures, since that is the first one Apple silicon runs. `mdd build`
passes it to hxcpp and clang as `MACOSX_DEPLOYMENT_TARGET`, without which hxcpp aims at 10.9, and
the bundle's `Info.plist` names it too, so an older Mac says the application needs a newer macOS
rather than failing to open it. A call into anything newer than that release stops the compile.
SDL comes from SDL's own release rather than from Homebrew, because Homebrew builds each bottle for
the macOS that built it, and an SDL built for macOS 26 does not load on anything older. SDL's
framework is built for 10.13 on Intel and 11.0 on Apple silicon, so it never asks for more than the
build does.

**The macOS installer is a bundle in a disk image**, signed ad hoc as a whole once everything is in
it. The program goes in `Contents/MacOS`, SDL's framework in `Contents/Frameworks`, and the fonts,
the icon atlases, the banks and the icon from `assets/icon/mdd.icns` in `Contents/Resources`,
because a bundle's signature expects nothing but code in the first two. The build stops if the
signature does not verify. Signing the program on its own is not enough: 1.0.2 shipped a bundle
nobody had signed around a program that was, and once downloaded, macOS called it damaged and would
not open it. `tools/icon/icon.py` draws the icon at the sizes macOS asks for, inside the margin a
Mac icon keeps.

**A Mac starts a program allowed 256 open files, and a build needs more.** clang holds more than
that at once compiling hxcpp's own runtime, 310 in one compile as measured, and stops with
`Too many open files`. `mdd build` raises the limit to 10240 for the compiler it starts on macOS,
wherever it is lower, so nothing has to be set by hand.

The website's pages are in `site/`. `layout.html` wraps every one of them, and a page asks for what
it shows from the document that describes it: `{{manual}}` and `{{contents}}` for the user manual,
`{{examples}}` for the example cards, read from the manual's table of them,
`{{readme:system-requirements}}` for the README section under that heading, and `{{playlist:<id>}}`
for a YouTube playlist, read from its public feed as the site is written, so a song added to it is
on the page the next time the site is published. The website never holds a second copy of any of
them, so it cannot drift from them. The pictures and the example audio are copied from `docs/`.
`./mdd site` run locally writes the same site the workflow publishes, and it opens straight from
disk. Served from a local web server it behaves exactly as it does on Pages, with the transitions
between pages and the player's scope, which a page opened from disk goes without. For the workflow's
result to land, the repository's Pages source has to be set to GitHub Actions.

**The Linux jobs pack a Debian package as well**, `md-synth-daw_<version>_<architecture>.deb`,
because the container installs `dpkg-dev` for them. It puts the program under `/usr/lib/mdd` and the
command under `/usr/bin`, depends on the system's own SDL3 rather than carrying one, which is the
copy apt keeps patched, and leaves out the three fonts a language downloads on demand, as the
portable archive does. A `packaged.txt` beside the program tells the application that apt updates
it, so its own updater never looks. What the package is called and who maintains it are the
`<debian>` element in `mdd.xml`. A `./mdd package` on a machine without `dpkg-dev` makes everything
else and says the package was left out.

The website serves those packages as an apt repository. `pages.yml` downloads the latest release's
`.deb` files and writes it with `./mdd site --apt debs`: the packages in a pool, a list for each
architecture written by `apt-ftparchive`, and a release file naming the lists by their hashes,
signed with the key in the `APT_SIGNING_KEY` secret. apt refuses a repository nobody signed, so
without the secret the website goes out without one, and the download page shows the apt
instructions only on a website that has it. The public half of the key is published beside the
repository as `md-synth-daw.gpg`, which is what a machine using the repository trusts.

The key is made once, without a passphrase, because the secret is what protects it:

```sh
gpg --batch --passphrase '' --quick-generate-key "MD Synth DAW apt repository" ed25519 sign never
gpg --armor --export-secret-keys "MD Synth DAW apt repository" | gh secret set APT_SIGNING_KEY
```

Keep a copy of it somewhere other than the secret. A lost key cannot be recovered from GitHub, and a
new one means every machine that added the repository has to fetch the new public key before `apt
update` trusts it again. Run locally, `./mdd site --apt debs` signs with the first secret key in the
keyring, or the one `MDD_APT_KEY` names.

<p align="right">(<a href="#top">back to top</a>)</p>

## The build file

There is no `.hxml` anywhere, and none is written by hand. Every option lives in `mdd.xml`: window
size, targets, defines, vendored sources, native sources, include paths and what each platform links
against. `if="windows"`, `if="linux"`, `if="mac"`, `if="debug"` and `unless="..."` gate any element.

The build generates `mdd.Config` from the window and meta attributes, the hxcpp `native.xml` from the
native, include and link elements, and the editor's completion files, one per target. None of those
is tracked and none is written by hand.

A `<target>` can hold `<define>` elements of its own, which reach that binary and no other. The
application's target defines `no_console` on a Windows release build, which makes it a windowed
program: it opens no console beside its window, joins the terminal it was started from if there is
one, and opens a console of its own when it is started with `-console`. A debug build and the gate
stay console programs, because both are read from a terminal.

Two elements put a shared library beside the binary, and which one applies depends on where the
library came from. `<ship>` copies a file or a folder the repository already has, which is how
Windows gets the vendored `SDL3.dll` and macOS gets SDL's framework. A folder is copied whole, links
and all, because a framework is a folder of links into itself and one copied file by file no longer
signs. The binary finds the framework through its own folder, which hxcpp gives every macOS program
as an rpath and which is where the framework sits in `export/bin` and in the portable archive, and
through the bundle's `Contents/Frameworks`, which the build file adds. `<carry>` names a library
linked from the system, which only Linux does, and the build finds the copy the binary actually
links and puts it in `export/bin`, where the rpath of `$ORIGIN` in the build file points the
binary at it. Without it the binary names the library and nowhere to find it, and the archive will
not start anywhere the library is not already installed.

The build file is deliberately not called `project.xml`. A file at the repository root with that
name, or `Project.xml`, `project.hxp` or `project.lime`, makes the Lime editor extension claim the
workspace and answer the Haxe language server with the output of a `lime` command that is not
installed here, leaving the editor with no completion at all and nothing saying why.

<p align="right">(<a href="#top">back to top</a>)</p>

## The shipped presets

The banks that ship are edited as text and shipped as records. `assets/presets/*.json` is one
document per bank, holding the presets with their names, icons and tags, and the build turns each
one into `export/banks/<name>.mdbank`, which is embedded in the binary as a resource. The
conversion runs only where a document is newer than the bank built from it.

That is where to fix a name or add a tag: edit the document, build, and the bank the application
offers is what you wrote. The records are the same format a preset or a bank saved from the browser
is written in, so nothing about a shipped bank is special beyond where it is kept.

<p align="right">(<a href="#top">back to top</a>)</p>

## Adding a check

The gate's programs live in `test/`, which only the `gate` target adds to its source path, so the
application binary cannot reach them. Everything the gate runs is one binary: `mdd.gate.Gate`
dispatches on its first argument to the `run(args)` each check exposes. Adding a program means
adding `run(args)` and a case in `Gate`, and nothing else.

The gate points the userdata folder at `export/gate/userdata` before any program runs, through the
`MDD_USERDATA` environment variable, so nothing a check saves, backs up or logs reaches your own
projects, backups or logs. The application reads the same variable, so setting it before starting
`mdd` keeps a separate set of settings and projects wherever it names.

`mdd gate` exits nonzero on any failure and is the only claim of working that counts. Every check
from the render path onward has an offline half, because a host being right is not the same as an
engine being right, and the only way to tell them apart is to render with no host anywhere near it.

A check that cannot run for want of something the repository does not carry returns `Gate.SKIPPED`,
which is 2. The gate names it in the summary and does not count it as a failure. Returning 1 for
missing data instead means nobody without that data can pass the gate, which is what `vgm` and `xgm`
used to do.

Thirteen programs answer to `mdd gate` without being part of it. They are outside `PROGRAMS`, so a run
of the gate never reaches them, because each either stops the process on purpose, writes a file into
the repository, or takes long enough that nobody would sit through it on every run.

| program | what it does |
| --- | --- |
| `mdd gate fault read \| write \| overflow \| thread` | stops the process on purpose, so the crash handler can be read back from `export/fault.txt`. `--window` opens a window and paints it for a few seconds first, so the report and the message box can be watched arriving over a live one, `--tell` raises the box without the window, and `--outside` writes the report under a folder named with letters outside ASCII instead, as an account named that way has |
| `mdd gate weigh` | measures what the heavy paths cost, a phase at a time, on a piece built to be worse than any real one. `--minutes <n>` sets how long to build, `--all` sweeps the whole register log corpus rather than the largest file, `--bounce` adds the block of audio an export holds, and `--ceiling <mb>` fails the run if anything goes past that many megabytes |
| `mdd gate shot <file>` | draws the whole interface into a PNG. `--project <file>` opens a project in it first, `--bar <px>` and `--from <bar>` zoom and scroll the playlist, `--renderer <name>` draws it through one SDL backend and `--frames <n>` presents that many first, which is how two backends are compared against each other. `--direct --sweep <file>` shows the window and zooms the playlist, or the roll with `--centre 1`, a wheel step at a time, writing each step's number into the file, so a capture taken from outside can say which step it saw. `--demo four`, `four-off`, `noise` or `moving` stages an example first: chords on FM3 with its four note mode on or off, a line on a tuned noise, or a bass line on FM4 played by a shipped preset whose own lanes move. `--ui <percent>` scales the interface, `--rack <row>` opens that channel's right click menu, `--hover <x,y>` rests the pointer there until its tooltip shows, `--reveal <pitch>` scrolls the roll to a note, and `--said <text>` sets the status line. `--pattern <n>` chooses a pattern and `--tool <n>` a tool, `--all` selects every note in the roll and `--pick <row,index>` picks a point on a lane. `--click <x,y>`, `--right <x,y>` and `--drag <x0,y0,x1,y1>` press there with the pointer, in the order given, each after a frame has been drawn. `--bounce <file>` writes the song as a WAV instead of a picture, with a stem beside it for every channel it sounds, through the output stage `--console <n>` names: 0 the chip alone, 1 a Model 1 and 2 a Model 2 |
| `mdd gate lift` | reads a preset bank out of a folder of recordings, with hand written tables of zone names |
| `mdd gate gather <folder> <name> <file>` | the same without the tables: it works a name out from the envelope a patch carries and the pitch it was played at |
| `mdd gate kit <file>` | writes the drum kit, every hit of it arithmetic rather than a recording |
| `mdd gate convert <folder> <file> [rate]` | turns a folder of recordings into a bank, working each hit's key out from the sound |
| `mdd gate bank <into> <presets folder> <project>[=kit]...` | reads finished pieces' own presets out of their project files and writes them as bank documents. Everything that is not a recording goes into the default bank and each piece's hits become a kit named after the `=`. A preset a shipped bank, the default set or the named presets folder already has is left out, which is how anything that arrived from elsewhere stays out of what ships. A `-` in place of the folder reads none |
| `mdd gate tidy <presets folder> [--delete]` | lists the files in a presets folder whose sound the library already offers, and removes them when told to |
| `mdd gate voice <into folder> [bank]` | renders every preset in a bank playing C0 to C7 and measures each note, so a name that claims something the sound does not do can be heard and seen |
| `mdd gate drift` | measures how far a converter run drifts from the rate it was written at |
| `mdd gate pulse` | measures where a recording's beat falls |
| `mdd gate swap` | reads what each renderer backend hands a frame to draw into, which is how deep its swapchain is |

A program that writes an asset is kept out of the gate on purpose. An asset that rewrote itself on
every run would show up as churn in a history that should only move when somebody decided something.

<p align="right">(<a href="#top">back to top</a>)</p>

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

<p align="right">(<a href="#top">back to top</a>)</p>
