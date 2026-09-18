# XGM notes

What the XGM format is, where its own documentation is ambiguous, and what `mdd.format.Xgm` assumes.
The format description is `bin/xgm.txt` in SGDK; the writer that actually produces the files is
`tools/xgmtool/src/xgm.c` in the same repository. Where the two disagree, this build follows the
tool, because the tool is what reads the file back.

## What XGM is

A driver format rather than a log. The Z80 runs the driver; the 68000 hands it a track and gets on
with the game. Music data is a list of commands grouped into frames: a frame ends with a wait, and
the wait is 1/60 of a second on NTSC and 1/50 on PAL. Everything inside a frame happens at once as
far as the driver is concerned, so **XGM timing is frame quantised and a VGM's sample timing is not**.
A VGM that writes a register 3 samples after another lands both in the same XGM frame.

The DAC is the driver's, not the music's. XGM mixes up to four PCM voices in software and writes the
sum to the YM2612's DAC, and it switches the converter itself: `src/snd/drv_xgm.s80` in SGDK writes
`$80` to `$2B` at the end of every frame a voice is live, keeps it there for three frames after the
last one stops, and then writes the value it saved at start up, which is `$00` and which nothing on
the 68000 side changes. FM6 therefore plays whenever no sample does. Raw writes to `$2A` and `$2B`
have no place in the music data, because the driver writes over both. That is why the export drops
them and the import puts them back by running the mixer and switching the converter the same way.
Checked on 18 September 2026.

**The rate is 14000 Hz exactly, and it is the driver's rather than the sample's.** Three places in
SGDK say so and none of them disagree: `bin/xgm.txt` describes "up to 4 PCM channels (8 bits signed
at 14 Khz)", `inc/snd/xgm.h` says the driver "supports 4 PCM channels at a fixed 14 Khz", and
`tools/rescomp/src/sgdk/rescomp/processor/WavProcessor.java` resamples every WAV handed to the
driver with `case XGM: outRate = 14000;`. The first two round it and the third does not, which is
why the number here comes from the third. Checked on 11 September 2026.

Whatever bytes a slot holds are played at that rate, so a sample authored at any other rate is
played at the wrong pitch unless it is resampled on the way in. That is what `Xgm.write` does, and
it is the reason a kit authored at 11025 Hz is converted a second time on export while one authored
at 14000 Hz is not.

The same file names the rates the other drivers in SGDK take, which is the nearest thing to a list
of what the machine is normally fed: 16000 for the plain PCM driver, 22050 for DPCM2, 16000 for
PCM4, and 13300 for XGM2, whose help text accepts only 6650 or 13300. The PCM driver's own help
text accepts 8000, 11025, 13400, 16000, 22050 and 32000.

## The header, and the part the description gets wrong

| where | size | what |
| --- | --- | --- |
| `$0000` | 4 | `XGM ` |
| `$0004` | 252 | the sample table, 63 entries of 4 bytes |
| `$0100` | 2 | the sample block size divided by 256 |
| `$0102` | 1 | the version, 1 |
| `$0103` | 1 | bit 0 PAL, bit 1 GD3 tags follow, bit 2 multi track |
| `$0104` | the block | sample data, 8 bit **signed** |
| `$0104` + block | 4 | the music data size in bytes |
| `$0108` + block | that | music data |

A table entry is two 16 bit little endian values: the sample's address divided by 256 and its length
divided by 256, both relative to the start of the sample block. Entry *n* is at `n * 4`, which puts
the first sample at `$0004` and makes the sample **ids one based**: a PCM command naming id 1 reads
the entry at `$0004`, and id 0 means stop.

Two things to know before writing one:

- **The description writes `$0104 SLEN` for the sample block and defines SLEN as the field's value.**
  Read literally that makes a 16 byte block where the same paragraph says 4096 bytes. The field is
  the block size divided by 256 in both places, and `xgmtool` reads the music offset as
  `(getInt16(data, 0x100) << 8) + 0x104`. A 16 bit byte count would cap samples at 64 kB, which the
  description's own "samples can be >32KB" rules out.
- **An empty table entry is address `$FFFF` and size `$0000`, not `$0001`.** The description says
  `$0001`; `xgmtool` writes `$0000` and reads an entry as empty when the address is `$FFFF` or the
  size is `$0100`. Writing `$FFFF` and `$0000` satisfies every reading.

## The commands

| code | size | what |
| --- | --- | --- |
| `$00` | 1 | end the frame and wait one |
| `$1X` | 1 + (X+1) | X+1 bytes to the PSG |
| `$2X` | 1 + 2(X+1) | X+1 register and value pairs to YM2612 port 0 |
| `$3X` | 1 + 2(X+1) | the same to port 1 |
| `$4X` | 1 + (X+1) | X+1 writes to the key register `$28` |
| `$5X id` | 2 | play sample `id` on PCM channel `X & 3` at priority `X & 0xC` |
| `$7E ddd` | 4 | loop to an offset from the start of the music data |
| `$7F` | 1 | the end |

X is four bits, so a run is at most 16 writes and a longer run is several commands.

## One command a slot

The driver's loop runs one command a slot, and a slot is 254 cycles of the 3.58 MHz Z80, the time
between two bytes to the converter; the cycle counts beside every path in `drv_xgm.s80` add up to
it. That is 71 microseconds. The writes inside one command are much closer: a `$4X` command writes
each byte 40 cycles after the last, 11 microseconds, which is inside one 18.8 microsecond sample of
the YM2612. The chip reads its key bits once a sample, so a key off and a key on for one channel in
the same command are no edge at all, and the note after them never strikes.

The export never puts two key writes for one channel in one command, and a register written after a
key write goes into a command after it, so writes reach the chip in the order they were made. The
import spreads the commands of a frame a slot apart for the same reason.

## What this build does with it

**Reading.** Frame waits advance the tick by 44100 divided by the rate, and each command inside a
frame lands a slot after the one before. Register writes go straight into `mdd.play.Stream`, so an
XGM reaches `mdd.format.Transcription` by the same path a VGM does and becomes an editable song. PCM
commands drive four voices through the same software mixer the driver uses: each output step sums
the live voices as signed bytes, clamps, and writes the result to `$2A`. The converter is switched on
when a voice starts, centred whenever every voice has run out, and switched off three frames after
that, which is what the driver does.

**Writing.** The register stream comes from `mdd.play.Sequencer`, the same producer everything else
consumes, and is cut into frames. `$2A` and `$2B` are dropped. The converter's notes come from the
sequencer too, which records each one as it sounds it: where it starts, where it ends and which
instrument plays it. A kit's hit is therefore the one its key picks, and a muted part sends nothing.
Each sample is resampled to 14 kHz, scaled by the converter's volume, converted from the YM2612's
unsigned bytes to signed, padded to a multiple of 256, and given a table entry. A note becomes a
`$5X` command in the frame it starts in, and a stop, `$5X` with id 0, in the frame it ends in where
its sample would still be playing, because that is where the piece stops it. Sixty three samples is
the ceiling and anything past it is counted rather than written.

The round trip is checked by `mdd gate xgm`: a song is written, read back, and every register the
song wrote has to come back holding the same value. The same program checks that a kit exports one
sample per hit and stops each where its note ends, that back to back notes keep their attack, and
that FM6 comes back once a sample is over.

## Still open

- **Priority is written as zero.** The driver's sixteen levels exist so a sound effect can take a
  channel from the music. Nothing in this application raises a sound effect yet, so nothing needs a
  level above the music's.
- **The loop command is never written.** A song has no loop point to write.
- **PAL export is untested against hardware.** The rate is taken from the song's tempo and written
  into the flags, and the frame length follows from it, but no PAL file has been played back.
- **XGM2 is not read or written.** It is a different format with its own command set.

## Tempo from a register stream

Neither a vgm nor an xgm carries a tempo. The importer had used the rate the file
was logged at, 150 for sixty hertz and 125 for fifty, which is right whenever the
driver happens to tick on a sixth of a frame and wrong the rest of the time. It
was wrong most of the time: across ninety six files only 33.7 per cent of note
onsets sat within a tenth of a sixteenth of the grid it produced.

### What is being measured

An onset is a key on, taken from register `$28` for the six fm channels and from
a psg attenuation leaving fifteen. Onsets closer together than two frames are one
onset, because six channels striking a chord are one event and counting them
separately buries the beat under its own harmonics. That single change is worth
more than any of the estimators tried around it.

The score for a candidate grid is the phase coherence of the onsets against it,
the length of the sum of unit vectors at angle `2 pi t / g`. It needs no
tolerance and no histogram, and it is exact for a driver whose timing is already
quantised to frames.

### Why not autocorrelation

It was tried first, on a five millisecond envelope, and it read 34 per cent
against the frame rate's 42 on the same files: worse than doing nothing. Two
reasons. Chords put a spike of six onsets in one frame and the correlation locks
onto that rather than the beat, and a driver that alternates eleven and twelve
frames to approximate a tick, as Green Hill's does, smears every peak.

Coherence against a grid is also the thing being measured, so optimising it
cannot do worse than the default by accident, where a separate estimator can.

### The search

The grid is a sixteenth, searched over the range a sixteenth can occupy between
60 and 220 beats a minute, in twelve hundred steps. Each candidate is weighted by
a log normal preference centred on 120 with a spread of half, which is what keeps
a piece from being read at half or twice its speed. The detected tempo is kept
only if it fits the grid better than the rate the file was logged at, so nothing
can come out worse than it went in.

| | on the grid | at the frame rate |
| --- | --- | --- |
| ninety six files | 81.5 per cent | 33.7 per cent |

Eighty one improved, none came out worse, and nine sit under half. The weakest is
Drowning at 28 per cent, which has no steady beat to find.

| | detected | on the grid |
| --- | --- | --- |
| Green Hill Zone | 150 | 94 per cent |
| Marble Zone | 133.24 | 82 |
| Star Light Zone | 125 | 98 |
| Emerald Hill Zone | 138.85 | 100 |
| Chemical Plant Zone | 139.44 | 95 |
| Casino Night Zone | 126.6 | 98 |
| Death Egg Zone | 84.4 | 97 |
| Final Boss | 99 | 100 |

Green Hill keeps 150 because 150 is right for it, which is the case the safeguard
exists for.

### The audio path, and why it is not the one used

A proper onset detection function was built and measured against the symbolic
one: render the stream, take a short time Fourier transform at a window of 1024
with a hop of 256, sum the half wave rectified difference of the magnitudes
across bins, remove a moving mean, and score candidate grids by the same
coherence, weighted by the strength of the function rather than by a count of
key ons. That is the standard pipeline and it is what "listening to it" means.

It lost, and not narrowly.

| over twenty four files | on the grid |
| --- | --- |
| register onsets | 94.3 per cent |
| spectral flux | 87.9 per cent |
| the rate the file was logged at | 51.5 per cent |

The flux was ahead on one of the twenty four and took ninety seconds against no
measurable time at all. Log compression of the magnitudes, which is the usual
remedy for exactly the failure seen, made it worse again at 83.3.

The failures are octave errors. Three of the boss cues are read at 187.5 by the
onsets, at 98 to 100 per cent on the grid, and at 93.75 by the flux, at 0 to 79.
Energy weighting is the cause: the loud beats dominate the function and the half
tempo wins, where a count of key ons keeps the finer grid.

It does not rescue the weak files either. On the nine that sit under half it
scores 38.0 against 37.2, ahead on two.

The reason is not tuning. A vgm is not a recording, it is an exact log of when
every note began, and estimating those times from rendered audio can only lose
information that was already there. The pipeline stays in the gate as the
measurement that says so, and the application carries none of it.
