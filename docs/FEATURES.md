# Everything MD Synth DAW does

The README is the short version. This is the long one: every feature the application has, and an
honest list of what it does not have and why. If something is not on this page, assume it is not
there.

- [Composing](#composing)
- [The eleven parts](#the-eleven-parts)
- [Instrument editors](#instrument-editors)
- [Presets and banks](#presets-and-banks)
- [Watching the hardware](#watching-the-hardware)
- [Playback](#playback)
- [Importing](#importing)
- [Exporting](#exporting)
- [The project file](#the-project-file)
- [Other](#other)
- [Keyboard](#keyboard)
- [What it deliberately is not](#what-it-deliberately-is-not)
- [What is not built yet](#what-is-not-built-yet)

---

## Composing

### The playlist

Clips laid over named tracks. A track carries its own name, colour and icon, and a clip that has no
colour of its own borrows the track's, so an arrangement reads at a glance.

Right clicking a track header offers: rename, auto name, auto name the clips, recolour, pick an
icon, clone, insert above, reset, mute, merge the clips, and delete. Clips can be dragged between
tracks, resized, sliced in two, and moved as a group. A clip knows where inside its pattern it
starts, so slicing one keeps the music where it was rather than restarting it.

A track can also drive one automation lane of a channel it does not otherwise own.

### The piano roll

- Click to write a note, drag to move it, drag an edge to resize it.
- Nine scales and twelve roots, chosen from the roll's own right click menu. Rows outside the scale
  are darkened and the root row takes the channel's colour.
- Snap, with `Alt` held to drop the grid mid drag.
- Zoom to fit, `Ctrl` and the wheel to zoom, middle drag to pan.
- Velocity per note.
- Parameter lanes underneath the roll, folded and scrolled.
- A note the chip cannot sound is hatched immediately, with a warning that clicks through to it.

### The tracker

The same pattern data as hexadecimal rows, for anyone who thinks in trackers rather than in rolls.
It is a view, not a second model: edits in either show up in the other.

### Automation

An editor holding every lane a channel has. Points carry a shape that curves into the next point
rather than only stepping or ramping. A held value is found by search rather than by walking every
point, so a long lane does not cost more to read than a short one.

Any parameter that corresponds to a register can be automated, including the ones that share a
register: `$B4` holds the stereo bits and both LFO sensitivities, and the automation lane owns the
whole byte so nothing else can fight it.

### Undo

Undo and redo cover everything, drags included. A drag lands as one step rather than one step per
frame. Renames, recolours, icon changes, track moves, pattern removals, channel changes, tempo
changes, nudges and slices are all on the same stack.

---

## The eleven parts

The ones the machine has, and no others:

| Part | Count | What it is |
| --- | --- | --- |
| FM | 6 | YM2612 four operator FM channels |
| Square | 3 | SN76489 tone channels |
| Noise | 1 | The SN76489 noise channel |
| Sample | 1 | The YM2612 DAC, which takes channel six when it is on |

Each keeps one colour everywhere it appears: the rack, the playlist, the roll, the scope and the
register timeline.

---

## Instrument editors

### FM

Every YM2612 parameter, laid out per operator: attack, decay, sustain rate, release, sustain level,
total level, multiple, detune, rate scaling, SSG-EG, and the channel's algorithm, feedback, LFO
amplitude and pitch sensitivity, and stereo.

The algorithm is drawn as separate wires rather than one line through every box, so which operator
modulates which is visible instead of implied. Envelopes are drawn per operator.

Hover any parameter and a tooltip names the register it writes, the raw value, and what the value
means:

```
Total level   OP4   register $4C   value 12   -9 dB
```

### Squares and noise

Attenuation, tone period and the noise mode, with a shaped envelope per channel. The noise channel
can take its period from the third square, which is one of the four rates the part's noise register
offers.

### Samples

WAV files import into the sample channel, resampled to the rate you ask for. A run of converter
writes is not one sample played at one rate, so the importer takes the rate from the gaps between
writes with real pauses excluded, rather than from the run measured end to end.

---

## Presets and banks

- Search by name or by tag.
- Any patch in a song can be lifted into the library.
- Patches import from TFI files and export back to them.
- Two banks ship, read out of VGM recordings of the Sonic the Hedgehog 1, 2 and 3 soundtracks and
  Mickey Mania. A patch is the value of a register at a key on, so forty two bytes of parameters
  the chip was set to.
- Your own patches load beside the shipped ones rather than replacing them.

---

## Watching the hardware

- **A register timeline**, saying which chip took each write and when.
- **A scope**, switching between waveform and spectrum.
- **A hardware meter** for what the song is asking of the parts.
- **Warnings that link to their cause.** Click one and it selects the channel and the note.
- **Hardware profiles.** Mega Drive and Master System, which is why the chips are named for chips:
  the Master System has the same PSG in it.
- **Three output stages.** The chip alone, the Mega Drive, or the Mega Drive 2, which differ in the
  filtering the board puts after the chips. The one pole at twenty hertz is the coupling capacitor
  the real board has, not an effect.

Everything above reads the same register stream that playback and the export read. There is one
producer of register writes in the whole program, so what is drawn cannot drift from what is heard,
and the checks compare the live stream against the offline one on every run.

---

## Playback

- Play, pause, stop and rewind, seek, and loop.
- Three polyphony behaviours: **strict**, where a part that runs out of voices drops the note;
  **stealing**, where the oldest voice gives way; and **arpeggio**, where notes beyond the channel
  count are cycled through it.
- Velocity mapping and tuning per part.
- A MIDI keyboard plays the channel you have selected, on a chosen device, channel and velocity
  curve.
- The audio device is opened stopped and primed with 100 ms before it starts, because a WASAPI
  device asks for more in its first few callbacks than the buffer size it reports.

---

## Importing

| Format | What comes across |
| --- | --- |
| **VGM** | The register stream becomes notes, patches, square envelopes and samples. Timing is kept as the file wrote it rather than a tempo being guessed at. The exact frequency word is recorded at every key on, so vibrato and slides survive rather than being rounded to the nearest semitone |
| **XGM** | Patterns and samples |
| **MIDI** | Notes and tempo |
| **WAV** | Samples for the sample channel, resampled to the rate you ask for |
| **TFI** | A single FM patch |

The VGM importer also analyses what it read: how many writes of each class the file makes, which
channels are used, and where the driver writes registers a note model cannot hold.

---

## Exporting

### Audio

WAV, FLAC, Ogg Vorbis and Opus. Set per export:

- sample rate, with a warning when it is below 44100
- bit depth, 16, 24 or 32
- mono or stereo
- silence before and after, and a fade, all typed in directly
- normalise to a ceiling, and dither
- encoder quality, and for Opus the application mode, frame size and bitrate mode
- which output stage the render goes through
- title, artist, album, year and comment, written into the file as tags

The FLAC encoder is this repository's own, written in Haxe from the format specification: LPC
prediction, partitioned Rice coding, stereo decorrelation and the MD5 signature, with no libFLAC
anywhere. Its files decode byte identical to the WAV written from the same samples, and its
signature matches libFLAC's.

The export is rendered offline at the rate asked for, not resampled from a 44.1 kHz render.

### Register and note formats

- **VGM**, which reads back as the same register stream it was written from.
- **XGM.**
- **MIDI**, which reads back as the notes it was written from.
- **TFI**, one patch at a time.

### The project

A zip or a folder, byte identical between runs. A zip's date field cannot hold anything before
1980, so the written date is fixed at 1980 rather than being a real timestamp that would make two
saves of the same song differ.

---

## The project file

`.mdsyn`, a zip of JSON documents plus the samples. The suffix can be registered with the desktop
so a double click opens it, and unregistered again from preferences. The JSON reader and writer are
this repository's own, because a `Map` insertion order is preserved on some Haxe targets and not on
hxcpp, and a project that reorders itself between saves is not byte identical.

---

## Other

- **Portable mode.** A `portable.txt` beside the executable, which the portable archive ships,
  keeps settings, projects and presets in a `userdata` folder next to the program rather than in
  your account directory.
- **It saves on its own** every five or ten minutes, or never, and only once something has changed.
  A song that was never saved by hand goes to a recovery file rather than nowhere.
- **Backups**, kept for as long as you set.
- **An updater that asks first.** It checks the releases page, and when there is something newer it
  says which version you have and which is offered, and gives you download, not now, or stop
  asking. Nothing reaches the network until you say so. It offers a portable copy an archive and an
  installed copy an installer, and for the right architecture, then replaces the files and starts
  the new copy.
- **A translatable interface.** Every string it shows comes from one table rather than from
  the code, so adding a language is a file rather than a change to the program. Hardware and
  format names are not in the table: `FM3`, `$4C`, `TL` and `bpm` stay as the documentation
  writes them in every language.
- **Themes, typefaces, interface density** and reduced motion, which follows the desktop setting
  unless you override it.
- **One instance.** Opening a second project hands it to the copy already running.
- **Discord presence**, off by default, speaking Discord's local IPC directly rather than through
  an SDK.
- **Crash reports that name the Haxe line**, out of a release build that carries no stack frames,
  written where your settings live. Functions the compiler inlined are named too, rather than the
  fault being blamed on the call site.

---

## Keyboard

| Key | What it does |
| --- | --- |
| `Space` | play or pause |
| `Ctrl+Space` | stop and rewind |
| `Ctrl+L` | loop the pattern |
| `Ctrl+Z`, `Ctrl+Y` | undo, redo |
| `Ctrl+S`, `Ctrl+O` | save, open |
| `Ctrl+E` | export a VGM |
| `Ctrl+Shift+E` | export audio |
| `Ctrl+,` | preferences |

A chord reaches the session after the focus chain declines it, so stopping playback while renaming
something works, and typing a space into a field does not start playback.

---

## What it deliberately is not

These are decisions, not gaps, and they are not going to change.

- **Not a general-purpose DAW.** No reverb, no filters, no oversampling, no parameter that does not
  correspond to a register on one of the two chips. Anything the hardware cannot do does not belong
  here, however ordinary it is elsewhere.
- **Not a plugin.** Not CLAP, not VST, not AU. This is an application, and the reason it is one is
  that a plugin could not be it.
- **Not an emulator.** No 68000, no Z80, no VDP. It produces and consumes a register stream; it
  does not pretend to be a console.
- **No second front end**, and no interface toolkit taken from anywhere.
- **No MP3 export.** Every encoder worth using is LGPL, and linking one in would put the whole
  application under obligations it does not want. Ogg Vorbis and Opus are BSD licensed and carry no
  such condition, which is why they are here instead.
- **No loudness normalisation.** Normalising is peak based: a -1 dB ceiling means the loudest
  sample lands at -1 dBFS. Nothing here measures LUFS.
- **No 32-bit build.** Sixty-four bit only.

---

## What is not built yet

Wanted, not present, and named here rather than implied by silence.

- **Stems.** There is no per-track or per-channel render yet. An export is the whole mix.
- **ROM and driver export.** Nothing produces a playable ROM or an SGDK driver blob.
- **Real hardware playback.** No link to a real Mega Drive, and no live parameter editing on one.
- **MIDI out.** A MIDI keyboard plays into the program; the program does not play out to a device.
- **Automatic pattern detection** in an imported VGM. Patterns come across as they were written,
  and finding the repeats is left to you.
- **Driver-specific optimisation** of an export for a particular sound driver.
- **Automatic polyphony optimisation**, where the program rearranges parts to fit the channel
  count on your behalf.

---

Where a claim on this page can be held by a check, `mdd gate` holds it, and the gate is the only
claim of working that counts here. It exits nonzero on any failure, and every check from the render
path onward has an offline half, because a host being right is not the same as an engine being
right.
