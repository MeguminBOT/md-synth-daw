# Preset notes

What a preset file holds, byte by byte, and how a preset's identity is worked out from it.
`mdd.format.Preset` is the reader and the writer. Nothing here is borrowed from another format.

## The file

A `.mdpreset` holds one preset and a `.mdbank` holds a bank of them. Both are the same layout;
a preset file simply names no bank. Numbers are little endian. Text is a 16 bit length followed by
that many bytes of UTF-8, at most 4096.

| bytes | what |
| --- | --- |
| 4 | `MDP1` |
| text | the bank's name, empty for a single preset |
| 2 | how many presets follow |

Each preset is:

| bytes | what |
| --- | --- |
| 1 | the part it was saved from, as `Part` numbers them |
| 2 | its icon plus one, so nought is no icon |
| text | its name |
| 1 | how many tags, at most 255 |
| text each | the tags |
| the rest | its sound record |

## The sound record

The part of a preset that decides what it sounds like, and nothing else. One byte says which of
three records follows:

- **0, a patch.** The four channel dials in order, algorithm, feedback, AMS and PMS, one byte each.
  Then each of the four operators in the order the synthesizer lists them: total level, attack,
  decay, sustain level, sustain rate, release, multiple, detune, key scale and SSG-EG, one byte
  each, followed by one byte that is 1 where the LFO reaches that operator. 48 bytes.
- **1, an envelope**, for a square or the noise channel. One byte for how many steps, at most 255,
  then one byte per step, then the loop step plus one as 2 bytes, so nought is no loop, then the
  speed and the noise control nibble, one byte each.
- **2, a recording**, for the converter. The rate in hertz as 4 bytes, the MIDI note it sounds at
  as one, the loop point plus one as 4, the length as 4, then the bytes as the converter takes
  them. A converter preset with no recording is written as a patch record of a fresh patch.

## Identity

A preset's identity is the MD5 of one byte for its family, 0 for FM, 1 for a square, 2 for the
noise channel and 3 for the converter, followed by its sound record exactly as above. It is written
as 32 lower case hexadecimal characters.

The family is taken rather than the part, so a patch saved from FM1 and the same patch saved from
FM4 are one preset. The name, the tags, the icon, the file it sits in and the folder above that are
all left out, so the same sound under another name in another folder is still the same preset,
and a project that plays it finds it wherever it has been moved to.

Anything that writes the same bytes gets the same answer, the way a FLAC signature is the MD5 of
the decoded samples whichever encoder wrote the file. For a square envelope of four steps, 15, 9, 4
and 0, looping to step 2 at speed 3 with a noise nibble of 5, the bytes are
`01 01 04 0F 09 04 00 03 00 03 05`. `mdd gate presets` checks that answer against the MD5 of those
eleven bytes.

Stars in the settings and each channel's record of the preset it was loaded from are kept by
identity. Before identity was taken from the sound alone it also covered the name, the tags and
the icon; `mdd.app.Formerly` still works that one out, once, to carry a star or a channel's origin
across, and nothing is written with it.
