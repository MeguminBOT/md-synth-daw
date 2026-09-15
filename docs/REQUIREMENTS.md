# What MD Synth DAW needs to run

The README has the short table. This is where the numbers in it come from, what happens to them
as a piece gets longer, and which machines fall outside them.

The figures here are measured rather than estimated: the memory, graphics and storage ones on a
release build with nothing else loaded, the C library versions out of each distribution's own
image. `mdd gate weigh` is the program behind the first set, and you can run it yourself.

- [The short version](#the-short-version)
- [Operating system](#operating-system)
- [Processor](#processor)
- [Memory](#memory)
- [Graphics](#graphics)
- [Storage](#storage)
- [Measuring it yourself](#measuring-it-yourself)

## The short version

| | |
| --- | --- |
| **OS** | Windows 10 or higher, macOS 26 or higher, or Linux |
| **CPU** | Any x86-64 or Arm64 processor, two cores or better |
| **RAM** | 1 GB |
| **GPU** | 256 MB, and integrated graphics is fine |
| **Storage** | 500 MB |

## Operating system

**64-bit only.** There is no 32-bit build for any platform, and there is not going to be one.

**Windows 10 or higher.** Anything older isn't supported, and nothing older ships a Direct3D 11
driver you would want.

**macOS 26 or higher.** The reason is Homebrew rather than the code. The macOS packages take the
SDL the build machine had, and Homebrew builds its bottles for the runner's own macOS, so that is
as far back as a package built here reaches, on Apple silicon and on Intel alike. macOS 26 is also
the last release Intel gets. Building from source on an older macOS aims at that one instead, and
the application itself has no macOS 26 requirement in it.

**Linux, and the version matters more than the distribution.** The packages are built inside a
Debian 13 container, whose C library is glibc 2.41, so that is the floor. Anything older refuses to
start with a message about `GLIBC_2.41` not being found, which is a build decision rather than a
fault in your system.

| distribution | what the packages want | its glibc |
| --- | --- | --- |
| Debian | 13 or newer | 2.41 |
| Ubuntu | 25.04 or newer | 2.41 |
| Fedora | 42 or newer | 2.41 |
| Arch, Manjaro, EndeavourOS | any current install, they roll | current |
| Linux Mint, Pop!_OS, Zorin | whichever release tracks the Ubuntu above | as its Ubuntu |
| openSUSE | Tumbleweed | current |

Those are read out of each distribution's own image rather than worked out from release dates. The
releases just below the line miss it by a little and still miss it: Ubuntu 24.10 has 2.40 and
24.04 LTS has 2.39, Fedora 41 has 2.40, and Debian 12 has 2.36.

**A current Raspberry Pi image is one of the machines this shuts out.** Raspberry Pi OS is built on
Debian 12, whose glibc is 2.36, so the packages here will not start on it. Build from source on the
Pi itself, or wait for a Debian 13 image.

If your distribution is older than that, build from source. It compiles against whatever C library
you already have, and then none of this applies.

**SDL does not need installing.** The Linux and macOS packages ship their own copy of SDL3 beside
the binary and find it there, which matters because SDL3 is new enough that a good many current
distributions do not package it yet.

**Older than any of the above isn't supported.** It may well run, and you are welcome to try, but a
problem on it isn't one we can look into. That covers a custom build aimed at an older Unix just as
it covers an old Windows: if the machine is outside the table, so is the help.

## Processor

**Two cores is a floor rather than a preference.** Synthesis runs on one thread and the interface on
another. On a single core the interface stutters whenever the chips are busy, which is most of the
time while something is playing.

**Nothing beyond the baseline instruction set is asked for.** No AVX, no AVX2, no anything a
processor from the last 15 years might be missing.

**Arm64 is built but not yet run on hardware here.** The Linux and macOS Arm packages come out of
CI and pass the same checks, on emulated and native runners respectively, but nobody has sat in
front of a machine running one. Treat it as working and tell us if it is not.

## Memory

**1 GB covers writing music.** With a piece open and nothing playing the application holds about
117 MB, peaking at 125 MB while it starts. That is the number to compare against a small machine.

**Exporting is what asks for more, and it grows with the length of the piece.** The register stream
is reserved in one block before anything is written to it, at roughly 30 MB for every minute of
music:

| length | the stream reserves | the whole process peaks at |
| --- | --- | --- |
| 2 minutes | 60 MB | 159 MB |
| 5 minutes | 150 MB | 260 MB |
| 8 minutes | 240 MB | 363 MB |
| 15 minutes | 450 MB | 599 MB |
| 30 minutes | 512 MB | 733 MB |

The reservation stops growing at 512 MB, which a piece reaches at around 17 minutes. Past that
the stream is large enough for anything the sequencer has been measured to put in it, with room to
spare: 30 minutes of 11 busy parts fills 1.7 million of the 33 million writes it holds.

An audio export holds the finished mixdown as well, at 44100 frames a second in stereo, which is a
further 10 MB a minute on top.

## Graphics

**The interface is 2D and never touches a 3D pipeline.** The card holds glyph atlases and a couple
of render targets rather than a scene, and sits at about 33 MB with a piece open. The 256 MB in the
table is room for a larger window on a denser display, not a measurement.

**Integrated graphics is fine**, and has been the whole time this was developed.

The renderer can be changed in the preferences or with `--renderer=`:

| backend | wants |
| --- | --- |
| `direct3d11` | Direct3D 11, feature level 10_0. Windows uses this unless told otherwise |
| `opengl` | OpenGL 2.0. Linux and macOS use this |
| `direct3d` | Direct3D 9 with Shader Model 2.0 |
| `direct3d12` | Direct3D 12 |
| `opengles2` | OpenGL ES 2.0 |
| `vulkan` | Vulkan 1.0 |
| `software` | nothing at all, and it draws on the processor |

Only Direct3D 11 and OpenGL are vetted with playback running. A backend that paints a still
interface correctly can still go wrong once the playhead, the scope and the meters are redrawing
every frame, which is how two of the others were caught. The rest are offered because the plumbing
is right, not because they are recommended.

## Storage

**500 MB, and most of it is not the program.**

| | |
| --- | --- |
| the program | 6 MB |
| the bundled typefaces | 45 MB, most of it the three CJK faces |
| an install, all told | 56 MB |
| while updating | about 150 MB, briefly |

An update downloads an archive and unpacks a whole second copy beside the first before swapping
them, then clears both away. The rest of the 500 MB is room for your own projects and the samples
in them, which is the part that actually grows.

## Measuring it yourself

`mdd gate weigh` builds a piece deliberately worse than any real one, 11 parts busy from end to
end with an automation lane on every register, and measures each phase separately. A thread samples
the process while each one runs, because a phase that reserves half a gigabyte and hands it back
reads as free from either side of it.

```sh
mdd gate weigh                    # 15 minutes, the default
mdd gate weigh --minutes 30       # or any length
mdd gate weigh --all              # sweep every register log in the corpus
mdd gate weigh --bounce           # add the block of audio an export holds
mdd gate weigh --ceiling 800      # fail if anything goes past that many megabytes
```

It prints the time, the peak, what is still held afterwards and what came out, a phase at a time.
The numbers on this page are its output.
