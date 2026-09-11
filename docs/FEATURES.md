# Everything MD Synth DAW does

The README is the short version. This is the long one: every feature the application has, and an
honest list of what it does not have and why. If something is not on this page, assume it is not
there.

The workflow draws on FL Studio: patterns written once and placed as clips on a playlist, a channel
rack down the side, and a piano roll with parameter lanes underneath it. If you have written music
that way before, you already know where things are. What those parts are wired to is the Mega
Drive, and that is where the resemblance stops.

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

Clips laid over named tracks, each track carrying its own name, colour and icon.

Right clicking a track header offers: rename, auto name, auto name the clips, recolour, pick an
icon, clone, insert above, reset, mute, merge the clips, and delete. Clips can be dragged between
tracks, resized, sliced in two, and moved as a group. A clip knows where inside its pattern it
starts, so slicing one keeps the music where it was rather than restarting it.

A track can also drive one automation lane of a channel it does not otherwise own.

### The piano roll

- Click to write a note, drag to move it, drag either end to resize it. A note too narrow to
  hold three handles keeps only the one on its end, so a short note can always be taken hold
  of and moved.
- Nine scales and twelve roots, chosen from the roll's own right click menu. Rows outside the scale
  are darkened and the root row takes the channel's colour.
- Snap to anything from a bar down to a sixty fourth, or to nothing at all, with `Alt`
  held to drop the grid mid drag. The grid is a division of a bar rather than a count of
  ticks, so it stays a sixteenth in a piece imported at 480 ticks a beat instead of
  becoming a sliver of one. The roll and the transport bar offer the same divisions, and
  the one you pick is kept between sessions. A note you place lands on the step you
  pointed at; one you drag goes to the nearest line.
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
changes, nudges and slices are all on the same stack, and so is everything the synth editors do:
every operator field, every dial, a whole envelope stroke, and mute, solo, pan and the channel
faders. Taking a sample out and normalising one are steps too, and taking one out moves every
instrument that named a later one along with it.

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

Every parameter is a bar you drag across, and it follows the pointer: the bar goes where you
take it rather than counting how far you moved. A click on one selects it without changing
it, a double click puts it back where a fresh patch has it, and the wheel steps a value four
at a time, or one with `Ctrl` held. The dials above the operators work the same way.

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

The converter plays one sample at a time like every other part. Switched to a drum kit from
its row in the channel rack, it reads the note instead: the pitch picks which sample sounds,
from the pitch each sample sits at.

The piano roll is the same keyboard either way. The keys the kit sits on are named for the drum
on them and the rest are drawn faint: a key with no sample still takes a note and still shows
it, and makes no sound. Turning the kit on can quieten notes written against whatever the
channel held on its own, which is what the row in the channel rack is for.

That is what lets a general MIDI drum pattern arrive intact. Channel ten of an imported file
goes to the converter with the kit already on, and the shipped samples sit at their General
MIDI drum notes, so a kick lands on the kick and every note stays on the key the file wrote it
on.

WAV files import into the sample channel, resampled to the rate you ask for. A run of converter
writes is not one sample played at one rate, so the importer takes the rate from the gaps between
writes with real pauses excluded, rather than from the run measured end to end.

---

## Presets and banks

- Search by name or by tag.
- Any patch in a song can be lifted into the library.
- Patches import from TFI files and export back to them.
- Four banks ship, read out of VGM recordings of the Sonic the Hedgehog 1, 2 and 3 soundtracks
  and Mickey Mania, 374 patches in all. A patch is the value of a register at a key on, so
  forty two bytes of parameters the chip was set to, and what is in a bank is exactly what the
  chip was set to rather than an approximation of it. Every preset is tagged with the tracks it
  came out of, so you can search for the sound you remember by where you heard it.
- Two drum kits ship for the converter. One is thirteen hits synthesised rather than recorded:
  a kick, a snare, three toms, closed, pedal and open hats, a clap, a rim, a crash, a ride and a
  cowbell. The other is ten hits in the manner of a TR-808. Every hit in both sits on the note
  general MIDI puts that drum on, so a drum track imported from a MIDI lands on the right hit
  with nothing to move.
- A bank costs the machine nothing until a note reaches for it. The sample counter reads what the
  music plays rather than what is loaded, the same way the channel counters do, so a new piece
  starts at nought however many banks ship.
- **The sample ceiling says what it is.** The converter takes one byte at a time and one sample
  sounds at a time, so a figure in bytes is storage, and how much storage there is depends on what
  you export: nothing at all for a render, no bank at all for a VGM, an XGM's own table for an XGM,
  and whatever you set aside for a cartridge. It starts at a quarter of a one megabyte cartridge,
  which is a convention rather than a limit of the machine, and you can set it to your own.
- Your own patches load beside the shipped ones rather than replacing them.

A preset arrives as a timbre with no loudness attached to it, because a driver keeps its
channel volume apart from the voice and adds it in at every key on. Loading one therefore
sets its carriers to the level a driver rests at, which is 22, so that a velocity has
somewhere to go and six channels together leave room above them. Measured across 112 register
logs and 120300 key ons, a carrier stands at 22 when the note arrives, and only 18 of those
key ons were at the top of the range. A patch read out of a recording or out of a TFI file is
left exactly as it was written, because it already carries the level it was played at.

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
- A monitoring fader with 20 dB of make up above unity, so a piece sitting in its headroom
  can still be listened to at the top of the scale. It is heard and never written: what
  makes an exported file loud is the normalising in the export panel.
- A MIDI keyboard plays the channel you have selected, on a chosen device, channel and velocity
  curve.
- The audio device is opened stopped and primed with 100 ms before it starts, because a WASAPI
  device asks for more in its first few callbacks than the buffer size it reports.

---

## Importing

| Format | What comes across |
| --- | --- |
| **VGM** and **VGZ** | The register stream becomes notes, patches, square envelopes and samples. Timing is kept as the file wrote it rather than a tempo being guessed at. The exact frequency word is recorded at every key on, so vibrato and slides survive rather than being rounded to the nearest semitone |
| **XGM** | Patterns and samples |
| **MIDI** | Notes and tempo. A file is looked through before any of it arrives, so you pick which of its tracks and channels to take and which part each one plays, and take it either as a piece of its own or as one more track in the piece you have open |
| **WAV** | Samples for the sample channel, resampled to the rate you ask for |
| **TFI** | A single FM patch |

The VGM importer also analyses what it read: how many writes of each class the file makes, which
channels are used, and where the driver writes registers a note model cannot hold.

A `vgz` is a gzipped VGM and is read as one, which is the form most recordings are handed
out in. Any of these opens by dropping the file on the window, by handing it to the program
on the command line, or from the file menu.

A MIDI taken into the piece you have open lands as one new track holding one pattern, at
bar one, with a lane for each part you chose. It keeps the piece's own tempo and counts in
the piece's own resolution rather than the file's, so what was already there does not
move. It goes on the undo stack whole.

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
- **stems**: one file per part beside the mix, in a folder named after it

The FLAC encoder is this repository's own, written in Haxe from the format specification: LPC
prediction, partitioned Rice coding, stereo decorrelation and the MD5 signature, with no libFLAC
anywhere. Its files decode byte identical to the WAV written from the same samples, and its
signature matches libFLAC's.

The export is rendered offline at the rate asked for, not resampled from a 44.1 kHz render.

A stem is that part rendered on its own, not the mix with everything else muted: the events of every
other part never reach the chips. Every stem takes the gain the mix worked out rather than being
normalised on its own, so the set of them sums back to the mix. Measured on a three part piece, the
stems sum to within -111 dB of the mix at worst and -138 dB once the output stage has settled.

Only the parts the arrangement actually sounds get a stem, so a piece using four channels gives four
files rather than eleven.

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
  writes them in every language. Which languages ship, and how each was translated, is in
  the README, and the sheet that asks for one on the first run says whether the language
  picked was written by a person or translated by a machine.
- **Themes, typefaces, interface density** and reduced motion, which follows the desktop setting
  unless you override it.
- **The pointer takes a shape over what it is on**: a double arrow on a splitter, on the line
  between two lanes and on either end of a note or a clip, an I-beam in a field, and the four
  pointed arrow with the pan tool in hand.
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
- **No pan pot.** The YM2612 gives a channel one bit for the left and one for the right, so
  a channel is on the left, on the right, on both, or silent. There is no sixty forty: the
  register has nowhere to put it. The squares have no stereo at all on a stock console, and
  the pan automation lane holds the whole of `$B4`, stereo bits and LFO sensitivities
  together, because that register has to have one writer.
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
