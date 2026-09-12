# Audio export notes

What the export path does, what is measured, and what is deliberately absent.

## The chain

`mdd.play.Mixdown` renders the song offline and hands back a float buffer:

1. The sequencer writes the register stream once, and `mdd.play.Render` renders it at the rate
   the export asks for. The chips are resampled by the same filter the live path uses, so an
   export at 96 kHz is not an upsampled 44.1 kHz render.
2. Silence is padded on at the front and the back.
3. A fade is applied over the last of it.
4. The peak is found and the whole thing is scaled so the peak lands on the ceiling.

`mdd.play.Mixing` carries the settings and the metadata. `mdd.view.Export` is the window over it,
and `mdd.view.Files` picks the writer.

Normalisation is peak based, not loudness based. A -1 dB ceiling means the loudest sample is at
-1 dBFS, which is what a tracker or a chip export wants; it says nothing about how loud the piece
feels. Nothing here does LUFS.

## FLAC

`mdd.format.Flac` is this repository's own encoder, written from the format specification.

It writes STREAMINFO, a VORBIS_COMMENT block for the metadata, and then fixed-size frames of 4096
samples. A stereo block is coded independently, as mid and side, as left and side or as side and
right, whichever of the four costs least. Each subframe is CONSTANT where the block does not move,
and otherwise the cheaper of a FIXED predictor of order 0 to 4 and a fitted predictor of order up to
12, with the residuals Rice coded across partitions rather than one parameter for the whole
subframe. The measurements at the end of this file are what each of those was worth.

Two things the format description makes easy to get wrong, both paid for here:

- **The blocking strategy bit decides what the coded frame number means.** Zero means fixed
  blocksize and the number is the frame index; one means the number is the first sample's index.
  Writing the frame index with the bit set produces a file every decoder rejects.
- **The CRC-16 covers the whole frame including the header and the header's own CRC-8.** Resetting
  it after the header gives a file that decodes and then fails verification.

**Verified against ffmpeg**, which is the only claim worth making about a format encoder: 16 bit
stereo, 24 bit stereo and 16 bit mono all decode to PCM byte identical to the WAV written from the
same samples, and the Vorbis comments read back as the tags they were given.

## Ogg Vorbis and Opus

libogg, libvorbis and libopus are fetched into `vendor/` by `mdd setup` and compiled straight into
the executable. `src/mdd/native/encode.cpp` is the whole of the glue: it builds the header packets, feeds
the encoder, and frames the packets into ogg pages. `mdd.format.Coded` is the Haxe side.

The build grew a `<tree>` element for it. Listing a hundred and thirty seven opus files by hand in
`mdd.xml` would be unreadable and would rot, so a tree names a directory, a suffix and the stems to
skip, and the build walks it when it writes `native.xml`:

```xml
<tree path="vendor/libopus/silk" suffix=".c" />
<tree path="vendor/libopus/src" suffix=".c" skip="opus_compare,opus_demo,repacketizer_demo" />
```

`<flag>` in the same section passes a C define through to the compiler, which is what `OPUS_BUILD`
and `USE_ALLOCA` need.

Three things cost a build each:

- **libvorbis and libopus both define `mdct_lookup`.** Putting `vendor/libvorbis/lib` on the include
  path makes celt's `mdct.h` and vorbis's `mdct.h` fight, and the error names a line in opus that
  has nothing to do with it. Neither library needs its own directory on the path: a C file that
  includes `"mdct.h"` gets the one beside it first. The include path carries only what a library
  reaches across directories for, which for opus is `celt`, `silk` and `silk/float`.
- **`DISABLE_FLOAT_API` is tested with `#ifndef`.** Passing `-DDISABLE_FLOAT_API=0` to keep the
  float API turns it off, and the failure is `opus_copy_channel_in_float` undeclared, a hundred
  lines from the define. Do not define it at all.
- **Opus insists on being told how to allocate temporaries.** Without `VAR_ARRAYS`, `USE_ALLOCA` or
  `NONTHREADSAFE_PSEUDOSTACK` it stops with an `#error`. MSVC has no variable length arrays, so
  `USE_ALLOCA`.

Opus is a 48 kHz codec, so the export window pins the rate to 48000 when Opus is chosen rather than
resampling behind the composer's back.

**Verified against ffmpeg.** Both files probe as the codec, rate and channel count they claim, both
carry their Vorbis comments, and Opus decodes to exactly the sample count it was given, which is
what says the pre-skip is written correctly. Vorbis decodes to 568 frames more than it was given,
and so does ffmpeg's own libvorbis encoder on the same input: that is the format's block padding,
not a fault in this glue.

## Not built yet

**MP3.** Every encoder worth using is LGPL: LAME, and the smaller `shine`.
  The licence table's position is that an LGPL source is built as a program of its own rather than
  linked, which is why the FM core is measured against Nuked-OPN2 rather than built from it. An MP3
  encoder linked into the application would put the application under the same obligation, so it
  is a decision rather than a default and it has not been taken.

The export window offers WAV, FLAC, Ogg Vorbis and Opus, because a format in the list that writes
nothing is worse than a format that is not there.

## The flac encoder measured against libFLAC

Encoding is lossless, so quality is not the question. What matters is whether the
samples come back, what the file costs, and whether a decoder can tell.

The encoder began with fixed predictors only, one Rice parameter for a whole
subframe, and channels coded independently. Those are the three things a real
encoder does that this one did not, and they were added in that order, measuring
after each against flac 1.4.3 on a 45 second stereo bounce.

| | bytes | of the wav | encode |
| --- | --- | --- | --- |
| where it started | 4428428 | 55.4 per cent | 162 ms |
| partitioned rice | 4364292 | 54.6 per cent | 269 ms |
| and mid and side | 3333327 | 41.7 per cent | 339 ms |
| and a fitted predictor at order 8 | 3236447 | 40.5 per cent | 540 ms |
| at order 12 | 3216239 | 40.2 per cent | 702 ms |
| flac -5, its default | 3239308 | 40.5 per cent | 110 ms |
| flac -8 | 3203209 | 40.1 per cent | 200 ms |

Mid and side is far the largest of the three on music, worth thirteen points on
its own. Partitioned residuals are worth under one, and the predictor about one
and a half.

Against the reference across five files, every one of them decoded by flac itself
and compared sample by sample with what went in:

| | ours | flac -5 | flac -8 | against -5 |
| --- | --- | --- | --- | --- |
| a mono tone | 54355 | 66485 | 66485 | -18.2 per cent |
| a stereo pair, both sides the same | 54506 | 66636 | 66636 | -18.2 per cent |
| one side silent | 54502 | 66632 | 66632 | -18.2 per cent |
| full scale sines | 212962 | 274698 | 274379 | -22.5 per cent |
| a real bounce | 3216239 | 3239308 | 3203209 | -0.7 per cent |

Plain material goes better here than in the reference because the partitioning is
allowed to go finer than its default and the fitted predictor suits a pure tone.
Music is where the reference's deeper search still shows, and at -8 it keeps four
tenths of a point.

### What it does

The predictor is autocorrelation over a Hann window, Levinson-Durbin for orders
one to twelve, coefficients quantised to fifteen bits with the shift chosen from
the largest of them and the rounding error carried forward. Every order is tried
and the cheapest kept, against the best of the five fixed predictors, so a block
that a fixed predictor suits still gets one.

The predictor sum is accumulated as a float rather than an integer. Twelve
coefficients of fifteen bits against a seventeen bit side channel reaches 2^35,
which a thirty two bit accumulator would wrap; a float carries integers exactly to
2^53, and `Math.ffloor` of the division is the arithmetic shift the decoder does.

### What was wrong with it

Reading a wav divided by 32768 and writing one multiplied by 32767, so a file read
and written again was not the file that went in. Encoding a full scale wav and
decoding it with the reference put 533854 of 800000 samples a step out, -32768
returning as -32767. It never showed on ordinary material, because the error only
reaches half a step above about half scale, and it showed on all of it at once
above that. Both directions go through one conversion now.

The signature was sixteen zero bytes, which is legal and means a decoder cannot
check what it produced. It is the md5 of the interleaved little endian samples
now, and it agrees byte for byte with what libFLAC writes for the same audio.

### Which to use

Ours. It is within half a point of the reference on music, ahead of it everywhere
else that was tried, and it signs its output. libFLAC is BSD-3 and would fit the
policy the ogg, vorbis and opus trees already sit under, so it stays open if the
last half point ever matters, but there is no longer a reason to reach for it.

One check in the mixdown had assumed a lossy file is smaller than a lossless one.
On a plain tone that is no longer true here: 16411 bytes of flac against 16698 of
opus at 128k. It now compares each against the wav instead.

## The json reader against haxe.Json

Both read the same ten documents: exponents, escapes, four digit unicode, nested
lists, empty objects. The reader was 4.5 times slower than `haxe.Json` on an 86 kb
bank and 3.25 times slower on a 13 kb language file.

Two things were doing it. Every character came through `charCodeAt`, which
returns `Null<Int>` and boxes on hxcpp, and every string was built one character
at a time through a `StringBuf`, which is expensive on a bank whose values are
long base64 runs with no escapes in them at all. Reading through
`StringTools.fastCodeAt` and taking an unescaped run in one piece, falling back
to the character loop only when a backslash appears, turns 1.36 ms into 0.20 ms.

| | ours before | ours after | haxe.Json |
| --- | --- | --- | --- |
| a shipped bank, 86 kb | 1.36 ms | 0.20 ms | 0.29 ms |
| a language, 13 kb | 0.27 ms | 0.07 ms | 0.08 ms |

Ours, then: it is now faster, and it hands back a typed `Node` rather than the
`Dynamic` that `haxe.Json` returns, which would put reflection at every read.

## Rendering the stems at once

A stem is the whole piece rendered with one part sounding, so the stems are
independent of each other and of the mix, and nothing in `play`, `chip` or
`song` holds a mutable static. Spreading an export of eleven stems across the
processors looks free, and it is not.

Four `Mixdown` instances rendering at once, each with its own `Render` and its
own `Stream`, fault inside the collector:

```
  it read an address that is not mapped
  hx::MarkContext::processMarkStack + 0x1F3
    Immix.cpp:1935
  GlobalAllocator::ThreadLoop + 0x7C
```

The same code with one worker instead of four passes, so the structure is
right and the concurrency is what breaks: every stem comes back byte for byte
what the same part renders to on one thread, and two exports of one piece
agree. Holding each worker's mixdown in an array slot that is read as well as
written, which is what fixed the single bounce worker faulting in
`Render.serve`, does not fix this one.

Where the main thread waits on the export it has to reach a safe point of its
own. A polling loop that allocates nothing never does, and the collector waits
for it forever: the first attempt hung rather than faulted, and wrote three
stems of six over four minutes.

`mdd gate stems` is what holds the property any later attempt has to keep. It
runs against one worker, and it is what says whether a change to spread the
bounce has kept the output identical:

| | |
| --- | --- |
| six stems, each against the same part rendered alone | byte for byte |
| two exports of one piece | byte for byte |
| one export of a two second piece | 1.01 s |
