# What ships that this repository did not write

Every file the application distributes, where it came from, its licence, and the date the licence
was read at the source. An asset that is not on this list does not ship.

Three licence shapes qualify: MIT-shaped permissive licences, CC0, and SIL OFL 1.1 on the bundling
reading below. Anything else is read for reference and never copied. An asset with no stated licence
is not a permissively licensed asset, however freely it circulates.

`vendor/` is fetched by `mdd setup`, is gitignored, and is never edited in place.

---

## Compiled into the executable

| source | version | licence | checked | fetched from |
| --- | --- | --- | --- | --- |
| miniaudio | 9634bed | public domain or MIT-0, at the user's choice | 2026-09-01 | github.com/mackron/miniaudio |
| stb_truetype | 1.26 | public domain (or MIT, dual) | 2026-09-01 | github.com/nothings/stb |
| libogg | 1.3.5 | BSD three clause | 2026-09-02 | github.com/xiph/ogg |
| libvorbis | 1.3.7 | BSD three clause | 2026-09-02 | github.com/xiph/vorbis |
| libopus | 1.5.2 | BSD three clause | 2026-09-02 | github.com/xiph/opus |

The first two are single headers compiled directly into `src/mdd/native/audio.cpp` and `src/mdd/native/text.cpp`.
Neither carries a distribution condition beyond the notice in its own source, which travels with
the header.

The three Xiph libraries are the audio export: libvorbis writes Ogg Vorbis, libopus writes Opus, and
libogg carries the pages both of them are framed in. Their sources are compiled from `vendor/` into
the executable by the `<tree>` entries in `mdd.xml` and are never edited. BSD three clause asks that
the copyright notice, the conditions and the disclaimer travel with a binary distribution; each
library's `COPYING` is fetched alongside its source and is what carries them.

There is deliberately no MP3 encoder. Every usable one is LGPL, and an LGPL encoder linked into this
executable would put the executable under the same obligation. That is a decision about what this
application is, not a build detail, and it has not been taken.

## Shipped beside the executable

| source | version | licence | checked | fetched from |
| --- | --- | --- | --- | --- |
| SDL3 | 3.4.14 | zlib | 2026-09-01 | libsdl.org |
| Qlementine Icons | e7cf96d | MIT | 2026-09-03 | github.com/oclero/qlementine-icons |

`SDL3.dll` is copied next to the program on Windows and linked from the system elsewhere. The zlib
licence requires that the origin not be misrepresented and that altered versions be marked as such;
this repository ships SDL unaltered.

**The interface icons.** `mdd setup` fetches the SVGs the icon manifest in `mdd.xml` names, at the
commit recorded in `vendor/qlementine/COMMIT`, and the build rasterises them into the atlases under
`export/bin/icons`. What ships is a bitmap rendering of the artwork rather than the artwork itself,
which the MIT licence permits: it asks only that the copyright notice and the permission notice
travel with the work, and `vendor/qlementine/LICENSE` is fetched next to the SVGs and ships beside
the program. The set is drawn at 16 and 24 pixels for desktop applications, which is the size the
interface draws it at, and its instrument category is what made it worth taking.

The manifest also accepts this repository's own SVGs under `assets/icons`, on the same terms and
through the same rasteriser. `wave-saw` and `wave-noise` are written here, because a general icon
set has no reason to carry them and this one does.

## Typefaces

Nine pairings ship and one is chosen in preferences. Every face is bundled rather than asked of the
operating system, which is what keeps the window identical on Windows, macOS and Linux. The
pairings and the faces they are built from are declared in `mdd.xml`, which is what `mdd setup`
fetches and what the preferences list is generated from, so adding one is a single edit.

Barlow Semi Condensed is also baked whichever pairing is chosen, and is what a label too long
for the pairing's own face is drawn in before anything is shortened. It is declared in the same
place, as `<condensed>`.

| face | licence | checked | fetched from |
| --- | --- | --- | --- |
| Go, Go Mono | BSD-3-Clause | 2026-09-01 | go.googlesource.com/image |
| IBM Plex Sans | SIL OFL 1.1 | 2026-09-01 | github.com/google/fonts, `ofl/ibmplexsans` |
| IBM Plex Mono | SIL OFL 1.1 | 2026-09-01 | github.com/google/fonts, `ofl/ibmplexmono` |
| Inter | SIL OFL 1.1 | 2026-09-01 | github.com/google/fonts, `ofl/inter` |
| JetBrains Mono | SIL OFL 1.1 | 2026-09-01 | github.com/google/fonts, `ofl/jetbrainsmono` |
| Barlow Semi Condensed | SIL OFL 1.1 | 2026-09-01 | github.com/google/fonts, `ofl/barlowsemicondensed` |
| Source Sans 3 | SIL OFL 1.1 | 2026-09-03 | github.com/google/fonts, `ofl/sourcesans3` |
| Source Code Pro | SIL OFL 1.1 | 2026-09-03 | github.com/google/fonts, `ofl/sourcecodepro` |
| Noto Sans | SIL OFL 1.1 | 2026-09-03 | github.com/google/fonts, `ofl/notosans` |
| Noto Sans Mono | SIL OFL 1.1 | 2026-09-03 | github.com/google/fonts, `ofl/notosansmono` |
| Fira Sans | SIL OFL 1.1 | 2026-09-03 | github.com/google/fonts, `ofl/firasans` |
| Fira Code | SIL OFL 1.1 | 2026-09-03 | github.com/google/fonts, `ofl/firacode` |
| Work Sans | SIL OFL 1.1 | 2026-09-03 | github.com/google/fonts, `ofl/worksans` |
| Roboto Mono | SIL OFL 1.1 | 2026-09-03 | github.com/google/fonts, `ofl/robotomono` |
| Open Sans | SIL OFL 1.1 | 2026-09-03 | github.com/google/fonts, `ofl/opensans` |
| Noto Sans JP | SIL OFL 1.1 | 2026-09-07 | github.com/google/fonts, `ofl/notosansjp` |
| Noto Sans SC | SIL OFL 1.1 | 2026-09-07 | github.com/google/fonts, `ofl/notosanssc` |
| Noto Sans KR | SIL OFL 1.1 | 2026-09-07 | github.com/google/fonts, `ofl/notosanskr` |

The last three are not interface faces and are never chosen in preferences. They are the fallback
chain: a glyph the chosen face has no outline for is cut from the first of them that does, one
glyph at a time, into the atlas the chosen face already owns. They carry kana, hangul and the CJK
ideographs, which no Latin face does, and together they are 38 MB of the 45 MB in `vendor/fonts`.
They are read from disk only when a codepoint first misses, so a session that never leaves Latin
never loads them.

**The bundling reading of OFL 1.1.** The licence permits a font to be bundled with software and
redistributed, with or without modification, provided the font is not sold on its own, the copyright
notice and licence travel with it, and no Reserved Font Name is used for a modified version. This
application bundles each face unmodified, keeps its licence file alongside it, sells nothing, and
renames nothing. Each family's `OFL.txt` is fetched next to its face and ships with it.

The Go faces are BSD-3-Clause rather than OFL, and their `LICENSE` ships alongside them for the same
reason.

## The shipped preset banks

`assets/presets/*.json` carry four operator FM patches read out of the VGM recordings in
`vendor/vgm`, which are soundtrack recordings of Mega Drive games. One bank per folder, each copied
beside the binary at build time and read at startup like any other bank a person drops in that
folder. Checked on 5 September 2026.

| bank | source | files | patches read | patches kept | read by |
| --- | --- | --- | --- | --- | --- |
| Sonic the Hedgehog | the game's soundtrack | 19 | 526 | 58 | `mdd gate lift` |
| Sonic the Hedgehog 2 | the game's soundtrack | 31 | 920 | 120 | `mdd gate lift` |
| Sonic the Hedgehog 3 | the game's soundtrack | 38 | 431 | 147 | `mdd gate gather` |
| Mickey Mania | the game's soundtrack | 24 | 177 | 27 | `mdd gate gather` |

Two programs made these because the first two banks were named by ear against hand written tables of
zone names, and the second two were not. `mdd gate gather` works a name out from the envelope a patch
carries and the pitch it was played at, and agrees with the hand naming on 107 of the 172 patches the
two overlap on, against 53 for always answering with the commonest name.

Neither program is run by the gate. Each imports each file, takes the patch
behind every instrument the import builds, and sets the carriers' total level to zero so that the
same timbre at two volumes counts once. A patch that matches one already kept is not stored again:
the track it came from is added to the one already there, which is why a patch can carry a great many
tags. These drivers reuse one instrument set across most of a soundtrack, so most of what is read is
a repeat.

Each patch is named for what it is, read from its algorithm, its carriers' envelope, its modulators'
frequency ratio and the register it was played in. It is tagged with every track it appears in, and
with the short form of a zone's name where the track is a zone.

**What these are.** A patch is the value of a register at a key on: an algorithm, a feedback, and ten
numbers for each of four operators. Forty two bytes of parameters that a chip is set to. They were
read from a recording of the hardware rather than copied from anybody's source, and this repository
makes no claim about them beyond recording where they came from, which is what this file is for.
Nothing here is a grant of permission, and the entry stands whatever the answer to that question is.

### The recorded samples two of those banks also carry

Two of the banks carry converter samples as well as patches, and a sample is not a parameter. These
are the bytes the converter was fed: an excerpt of the game's audio rather than a setting the chip
was put into, so the paragraph above does not reach them.

| bank | samples | bytes | what they are |
| --- | --- | --- | --- |
| Sonic the Hedgehog | 4 | 40744 | Kick, Snare, Timpani, and a voice saying the publisher's name |
| Sonic the Hedgehog 2 | 8 | 49012 | Bongo, Clap, Kick, Scratch, Snare, Timpani, Tom, and that voice |

They are recorded here because this file is the register of what ships. Whether they should ship at
all is a decision rather than a fact, and it has not been taken.

## The drum kit

`assets/presets/drum-kit.json` is written by `mdd gate kit`, which the gate does not run. Nothing in
it is recorded or sampled from anywhere: every hit is arithmetic, built by `test/mdd/gate/Kitted.hx`
and covered by this repository's own licence like any other file in it. A drum is a sine swept down
under a falling envelope, a cymbal is noise with its low end differenced away, and a cowbell is two
tones built from the odd harmonics that fit under half the sample rate. The noise comes from a
counter with a fixed seed, so the bank is the same bytes on every run.

| what | root | bytes |
| --- | --- | --- |
| Kick | 36 | 2425 |
| Rim | 37 | 496 |
| Snare | 38 | 1984 |
| Clap | 39 | 2094 |
| Tom low, mid, high | 41, 45, 48 | 3748 each |
| Hat closed, pedal, open | 42, 44, 46 | 496, 826, 3528 |
| Crash, Ride | 49, 51 | 9371, 6063 |
| Cowbell | 56 | 2866 |

Thirteen hits, 41393 bytes at 11025 Hz, which is 15.8 per cent of the 262144 the Mega Drive profile
allows for samples. The roots are where general MIDI puts each drum, so a drum track imported from a
MIDI lands on the right hit with nothing to move.

## The 808 kit

`assets/presets/retribution.json` is this repository's author's own work rather than anybody
else's: ten hits built in the manner of a TR-808 and converted here, so it is covered by this
repository's own licence like every other file in it. Mono, eight bit unsigned, 11025 Hz, the
same shape the synthesised kit uses, and each hit sits where general MIDI puts that drum.

| what | root | bytes |
| --- | --- | --- |
| Kick | 36 | 2405 |
| Snare, Snare 2 | 38, 40 | 3149, 1946 |
| Tom low, mid, high, top | 41, 43, 45, 47 | 10967, 7218, 10520, 12599 |
| Hat closed | 42 | 3041 |
| Crash, Crash 2 | 49, 57 | 18900, 9605 |

Ten hits, 80350 bytes, which is 30.7 per cent of the 262144 the Mega Drive profile allows for
samples. None of that is spent until a note reaches for a hit: a bank sitting in the library
costs the machine nothing.

## Read but never shipped

| source | licence | why it is here |
| --- | --- | --- |
| Nuked-OPN2 | LGPL-2.1 | the known-good YM2612 the FM core is measured against |

Nuked-OPN2 is built as programs of its own under `export/bin/opn2-*`, which the packaging step
excludes by name. Nothing it defines is linked into the application, and no line of it is copied
into `mdd.chip`. Porting it would place that module under the LGPL, which would be a decision rather
than a default.

The chip cores in `mdd.chip` are this repository's own, written from the part documentation and
established by measurement against that reference. That is what `docs/notes/ym2612.md` records, and
it is why the reference's licence does not reach them.

Hardware behaviour is taken from documentation or established by measurement. It is not taken by
reading a restrictive source and transcribing what it does: a number lifted out of somebody else's
emulator is that emulator's answer, and it arrives with no way to tell a measurement from an
approximation somebody settled for.
