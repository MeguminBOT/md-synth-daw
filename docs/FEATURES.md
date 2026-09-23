# Everything MD Synth DAW does

The README is the short version. This is the long one: every feature the application has, and an
honest list of what it does not have and why. If something is not on this page, it is not there.

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

Drawing lays a clip where you press and another for every length of it you drag across, so four
bars of a pattern is one stroke rather than four clicks, and the whole run undoes in one step.

Double click a clip to open it: a pattern opens in the piano roll with one of its channels chosen,
and an automation clip opens in the automation editor. The roll and the automation editor number
their bars from where the pattern sits in the song, so a pattern placed at bar 53 reads bar 53 there
too, and scrubbing them moves the song to that bar. A pattern placed more than once follows the clip
playing it, or else the one you opened it from.

The triangle in a clip's corner opens its menu: open it, make it unique, rename its pattern, copy,
cut, paste, delete, or move it an octave. A new pattern is called Pattern and a number no other
pattern has, and auto naming a track's clips calls its patterns after the track, numbered in the
order they first play.

A track can also drive one automation lane of a channel it does not otherwise own. A note that starts
under that clip starts on what the clip holds, the same as under a lane in its own pattern, so a
clip panning a channel keeps it panned from note to note.

### The piano roll

- Click to write a note, drag to move it, drag either end to resize it. A note too narrow to
  hold three handles keeps only the one on its end, so a short note can always be taken hold
  of and moved.
- Sweep the right button with the pencil out, or the left with the rubber, to take a run of
  notes away in one step. Hold `Shift` and drag a note to carry a copy of it, or of the whole
  selection, away from the one you started on.
- Nine scales and twelve roots, chosen from the roll's own right click menu. Rows outside the scale
  are darkened and the root row takes the channel's colour.
- Snap to anything from a bar down to a sixty fourth, or to nothing at all, with `Alt`
  held to drop the grid mid drag. The grid is a division of a bar rather than a count of
  ticks, so it stays a sixteenth in a piece imported at 480 ticks a beat instead of
  becoming a sliver of one. The roll and the transport bar offer the same divisions, and
  the one you pick is kept between sessions. A note you place lands on the step you
  pointed at; one you drag goes to the nearest line.
- `Ctrl` and the wheel to zoom, as far out as a bar four pixels wide and as far in as one
  two thousand wide, wherever the pattern happens to end. `Ctrl` and the wheel over the
  keyboard, or with `Shift` held anywhere, makes the rows taller or shorter instead. Middle
  drag to pan, and zoom to fit from the right click menu to get back. The view scrolls four
  bars past the end of the pattern, which is shaded so the end still reads as one.
- `Ctrl`+`B` lays a copy of what you have selected straight after it. The gap is rounded up
  to a beat, a doubling of one, or a whole bar, so a bar of drums whose last hit stops short
  of the bar line still copies onto the line instead of drifting forward each time.
- `Ctrl` and an arrow moves a note by an octave, `Shift` and an arrow leans it louder or
  quieter, and an arrow on its own still moves it by a semitone or a grid step.
- Quantise, legato, glue, tie and untie, from the roll's right click menu. Each acts on what you
  have selected, or on the whole channel where you have selected nothing, and each undoes in one
  step. Quantise is the one an import wants: a driver writes a key on wherever its own timer
  landed, so almost nothing read out of a register log starts on a line.
- **Tie** joins each note to the one before it, the way a driver plays a legato line. An FM
  channel changes pitch with no new key on, and a square without starting its envelope again,
  so the line slides from note to note instead of striking each one. A tie is drawn as a stroke
  joining the two notes, and ties read out of an imported file show the same way.
- Velocity per note, and a drag across the velocity strip paints every note it passes. A note
  that is part of a selection leans the whole selection by the same amount instead, so the
  shape of a phrase survives a change of level.
- Parameter lanes underneath the roll, folded and scrolled.
- **Fill**, from the right click menu on an empty spot, puts a note on that row every step, every
  2 or 4 steps, every beat, every 2 beats or every bar across the pattern, and leaves any note
  already starting there alone.
- A note the chip cannot sound is hatched immediately, with a warning that clicks through to it.

### The tracker

The same pattern data as hexadecimal rows, for anyone who thinks in trackers rather than in rolls.
It is a view, not a second model: edits in either show up in the other.

Notes are named the same way everywhere, as the Editing preferences say: with sharps or with flats,
and with the letters C to B or, as German does, C to H, where B is B flat. A note typed into the
tracker is read by the same rule.

### Automation

An editor holding every lane a channel has. Points carry a shape that curves into the next point
rather than only stepping or ramping. A held value is found by search rather than by walking every
point, so a long lane does not cost more to read than a short one. The square on a lane's header
maximizes it, folding every other lane to its header until you press it again, which is the room a
wide range such as a frequency needs.

The scale beside a lane zooms what the lane shows. Turn the wheel over it to zoom in or out around
the value under the pointer, and drag it to move the values shown. Double click it to fit the lane
to its points and again to show every value, or right click it to pick a span either side of nought.
A vibrato a dozen frequency steps wide then fills the lane instead of drawing as a flat line, and a
point you add lands on the value drawn where you pressed.

Any parameter that corresponds to a register can be automated, including the ones that share a
register: `$B4` holds the stereo bits and both LFO sensitivities, and the automation lane owns the
whole byte so nothing else can fight it.

A lane holds its value from one note to the next, the way a register does on the chip. A note starts
at whatever its lanes hold where it begins, a level lane included, even though a key on loads the
whole preset, and a note before a lane's first point takes that first point's value. A level lane on
a square or the noise channel takes the place of the instrument's envelope, and stays silent in a
rest rather than sounding the channel again.

A **preset lane** lets one channel play several instruments in turn. Right-click a preset and
choose to switch the channel at the playhead: from that point on, every note loads the whole preset
at its key on, including a note that names an instrument of its own. That is how a driver changes
voice, so what reaches the chip, and what an export carries, is the ordinary register writes of a
patch. Before the lane's first point the channel plays what it did before. A point names a preset
the song itself carries, and a saved project carries every one of them in order, so a project
opens with the same switches on a machine with a different set of presets installed. The sample
channel has no preset lane, because a kit picks each hit by the note.

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

The chip has one LFO for every channel, so a preset only says how deeply its channel takes it. The
LFO itself belongs to the song: the LFO field in the transport bar switches it off or picks one of its
eight rates, shown in hertz as the chip runs them, and a change is heard straight away.

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

WAV files import into the sample channel, band limited on the way down so nothing above the new
half rate folds back into what is kept: measured, a tone the new rate cannot carry leaves 75.6 dB
below one it can.

**A kit is made in a sheet of its own.** It opens empty and you fill it, a file or a whole folder
at a time, because a kit is as often gathered from several places as it is found sitting in one. Name
it, tag it, and every WAV you add becomes a hit: the offset comes out, the silence before and the
tail past hearing are cut, the rate is brought down band limited, the end is faded so a cut does not
click, and the loudness is set before the bytes are made rather than by scaling bytes afterwards. The
rates offered are the ones Mega Drive drivers actually take, 14000 among them, which is what the XGM
driver plays at.

Detect keys puts every hit on a key. A file name that spells a note, such as `A#3`, `Eb4` or a
tracker's `C-4`, puts the hit on exactly that key, with middle C as `C4`, because a pack that names
its keys has already said where each one goes. Everything else is worked out from the recording
rather than from its name, because a name that says what a hit is is often wrong: a hat that chokes
is the closed one and a hat that rings is the open one whatever either is called, and toms are
ordered by their measured pitch so a fill runs low to high however they were numbered. With General
MIDI drums off, those hits are laid out one after another from C2 in the order their names read, so
`Hit 2` comes before `Hit 10`. The list is shown in key order, every key can be moved by hand, and
the running total is shown against what you have set aside. A run of converter
writes is not one sample played at one rate, so the importer takes the rate from the gaps between
writes with real pauses excluded, rather than from the run measured end to end. A byte that is
never written because the converter already holds it is kept for as long as the gap lasts, so a
sample keeps its length, and a hit cut short by its note is read as the recording it was cut from.
A VGM this application wrote therefore imports with its drums where they were.

---

## Presets and banks

- Search by name or by tag. The search also takes words that narrow it: `tag:bass` keeps presets
  with a tag holding bass, `bank:sonic` keeps the banks whose name holds sonic, a `-` in front of
  any word leaves out what it matches, a phrase in quotes is taken whole, `fav` keeps your
  favourites and `used` keeps what the open piece plays.
- The browser opens with every bank folded, so the first thing you see is the list of banks
  rather than the first one's presets. Its buttons sit on a row of their own under the search,
  and follow the sidebar however narrow you drag it.
- **Group** lists the presets of each family by bank, by tag, by when they were added, by where
  they come from, which is the Default bank, the banks that ship, your own or the open piece, or
  in one list with no groups at all. The four families, FM, PSG, NOISE and DAC, stay at the top
  whatever you pick, and the Default bank is always the first group in them.
- **Sort** puts them in order by name, by date added, by how alike they are to what the chosen
  channel plays, or as their bank lists them, and **Reverse** runs it the other way. A number in
  a name is read as a number, so `Patch 2` comes before `Patch 10`.
- **Filter** shows or hides each source, keeps only your favourites or what the open piece uses,
  shows a sound that sits in several banks only once, and keeps only the presets carrying the tags
  you tick. **Hide bank**, on a bank's right-click menu, takes a bank out of the list until you
  bring it back from the same menu. The button counts the filters that are on, and **Clear
  filters** turns them all off. The grouping, the sorting and the filters are kept between
  sessions.
- A preset's date added is when its file first appeared in your presets folder. It stays with the
  preset through a rename, new tags or a move to another folder, because it is kept by what the
  preset sounds like.
- **Load into**, on a preset's right-click menu, lists every channel the preset plays on, each
  with what that channel plays now beside it, so you can load into a channel you have not
  selected.
- **Switch at playhead**, on a preset's right-click menu, puts it in the channel's preset lane
  where the playhead is, so one channel can change instrument part way through a pattern.
- Any patch in a song can be lifted into the library.
- Patches import from TFI files and export back to them, and one preset writes out as a TFI from
  its right-click menu. A TFI is forty two bytes of registers and nothing else, so a name, tags and
  the two LFO depths stay behind; everything the format carries comes back exactly.
- **A preset goes back to what it was.** Loading one into a channel gives the channel its own copy
  of it, so playing with the knobs never touches the preset. Choose the same preset again and every
  field goes back to what it held when you loaded it, in one undo step. Right-click a single dial
  in the synthesizer, or a step of a square or noise envelope, to put that one parameter back and
  leave the rest as you have it.
- **A preset is what it sounds like.** What makes one preset that preset is its patch, its
  envelope or its recording, and nothing else: not its name, its tags, its icon or the folder it
  sits in. Rename one, retag it or move it to another folder and it is still the same preset,
  and the same sound saved twice under two names is one preset. That identity is an MD5 over the
  sound laid out byte by byte in `docs/notes/presets.md`, so anything that writes the same bytes
  gets the same answer.
- **A star is on the preset, not on the row.** Favourite one from its right-click menu and the
  browser marks it wherever it appears, in this piece and in every other, and under whatever
  name. **Favourites only** in the filter menu, or `fav` in the search, lists the starred on
  their own. A preset you edit into something else is a different preset and keeps no star.
- **The Default bank is built into the program**, and it is the one bank that is. Everything
  else that ships, the game banks and the drum kits, is written into your presets folder as files
  the first time you start the program, under the family folders like anything of your own, so
  you can rename, change or delete any of it. A bank you delete stays deleted. When a newer version
  ships a bank that changed, it replaces your copy only where you left that copy exactly as it
  was written.
- **67 of the Default bank's FM patches are by ulalume**, under CC0 and credited in the README:
  pianos, guitars, basses, brass, strings, organs, pipes, tuned percussion, synth leads and pads,
  each tagged with the family it belongs to.
- Four banks ship, read out of VGM recordings of the Sonic the Hedgehog 1, 2 and 3 soundtracks
  and Mickey Mania, 374 patches in all. A patch is the value of a register at a key on, so
  forty two bytes of parameters the chip was set to, and what is in a bank is exactly what the
  chip was set to rather than an approximation of it. Every preset is tagged with the tracks it
  came out of, so you can search for the sound you remember by where you heard it.
- **The bank every piece opens with is Default**, 131 presets: ulalume's 67 and 64 lifted out of
  the finished pieces this program was written alongside, 35 FM patches, 14 square envelopes and
  15 noise ones. Leads,
  basses, pads, plucks, bells, organs, guitars, brass and strings for the FM channels; hats,
  crashes, rides, sweeps and shakers for the square and noise ones. Each is named for what it is
  for and tagged with what it is good for, `Bass`, `Pad`, `Bright`, `Hard`, so a search on a use
  finds everything that serves it.
- Seven drum kits ship for the converter, named for the music they suit. One is thirteen hits
  synthesised rather than recorded: a kick, a snare, three toms, closed, pedal and open hats, a
  clap, a rim, a crash, a ride and a cowbell. **808** is ten hits in the manner of that machine.
  **Ambient**, **Pop**, **Trap**, **Dubstep**, **Gabber** and **Hardcore** came out of finished
  pieces, from three hits to fourteen, the last of them carrying vocal stabs as well as drums.
  Every hit in the first two sits on the note general MIDI puts that drum on, so a drum track
  imported from a MIDI lands on the right hit with nothing to move.
- **Sort by how alike they are.** **Similar**, under **Sort**, puts the presets closest to what
  the chosen channel is playing first, with how alike each one is beside it as a percentage.
  Every parameter counts once and each is worth how far apart the two are over how far apart
  they could be, so a total level four steps away costs almost nothing and another algorithm
  costs a whole field. Half a range apart on average reads as nothing in common, because two
  patches picked at random sit a third of a range apart and would otherwise all read as two thirds
  alike.
- **A kit is a bank, and that is why each one is separate.** A drum note picks its hit by note out
  of the bank the sample channel's own preset sits in, so two kicks on the same key cannot share a
  bank: whichever came first would be the only one you ever heard. That is the one thing banks
  decide rather than only show.
- A bank costs the machine nothing until a note reaches for it. The sample counter reads what the
  music plays rather than what is loaded, the same way the channel counters do, so a new piece
  starts at nought however many banks ship.
- **The sample ceiling says what it is.** The converter takes one byte at a time and one sample
  sounds at a time, so a figure in bytes is storage, and how much storage there is depends on what
  you export: nothing at all for a render, no bank at all for a VGM, an XGM's own table for an XGM,
  and whatever you set aside for a cartridge. It starts at a quarter of a one megabyte cartridge,
  which is a convention rather than a limit of the machine, and you can set it to your own.
- **A saved preset reaches every project.** Saving a channel as a preset writes it into your
  presets folder as a file of its own, and the browser offers it in every project from then on,
  including projects made before it. It keeps everything the channel has: the whole patch with its
  LFO depths, a square or noise envelope, or a sample with its loop. Saving again under the same
  name replaces it.
- **Open folder**, on the preset browser's toolbar, opens the presets folder in your file
  manager. It holds a folder for each family of part, `FM`, `PSG`, `NOISE` and `DAC`, and a
  preset you save goes into the one its part belongs to. Those four are not categories
  themselves: a preset sitting loose in one is a saved preset, while a subfolder you make inside
  one is a category of its own, named for the folder, and shows in the browser even while it is
  empty. A preset moved from one folder to another moves to that category as soon as you come back
  to the window. Patch files and bank documents work in any folder, and a folder filled before
  this layout is sorted into it once, the first time you open the program after the change.
- **Organise it from the browser.** A preset in your folder can be renamed, retagged, given an
  icon, moved or copied into another category, or deleted from its right-click menu, and every
  change is made to its file, so the folder and the browser always agree. A patch file given a
  name or tags it has no room for becomes a preset file. **Copy to** also works on a preset that
  ships, which is how you get a copy of one to change. **New category**, on a family's right-click
  menu, makes a folder for one, and a category's own menu renames it, tags it or deletes it.
  Nothing is erased: a deleted preset or category is moved into a `presets` folder inside your
  backups, and kept there as long as a backup is.
- **A category has tags of its own**, and every preset in it answers to them in the search, the
  filters and grouping by tag. A folder keeps its tags in a `.tags` file inside it, so they move
  with it, and a bank file keeps them inside itself.
- **A preset is a file you can hand to somebody.** One writes out as `.mdpreset`, a
  **MD Synth Preset File**, and a whole bank as `.mdbank`, a **MD Synth Preset Bank**, from the
  right-click menu on a preset or on a bank heading. Both are the same format: the parameters as
  numbers rather than as text, every recording a converter preset plays included, so a kit travels
  whole. Dropping one on the window or **Import presets** in the file menu adds it to your
  presets: a single preset goes into the **Imported** category of its family, a bank keeps its own
  name, and the browser offers them in every project. Where a bank holds presets you already have,
  you are asked first whether to import them anyway, skip them, or combine their tags so that each
  copy carries both sets. The piece you have open is left as it is until you load one of them.
- **Double click a preset or a bank on the desktop** and it is imported the same way, since both
  suffixes register with the desktop. With the program closed, it does not open a window: a small
  box asks about duplicates where there are any, then says what was imported, or what went wrong,
  and offers to open the program. With the program running, the file goes to it, and a sheet says
  what was imported.
- **A hit writes out as a wave file.** A converter preset's right-click menu writes what it plays
  at the rate it was recorded at, so you can take a hit into anything that edits sound and bring it
  back in.
- Your own presets load beside the shipped ones rather than replacing them.
- **A project file is the piece, not your preset folder.** It carries what the piece plays: the
  eleven presets on its channels, the ones its notes and preset lanes name, and the whole of the
  kit behind its sample channel. Nothing else goes in. A preset is copied into a piece when you
  load it, not before, so the browser's banks are never part of a piece, and a preset you tried in
  a channel and moved on from is left out when you save. A file therefore does not grow as your
  folder does, and it still opens the same on a machine that has none of your presets, because
  everything it plays is in it. A new piece carries eleven presets.

  An older project opens as it was and sheds what it does not play the first time you save it.
  One piece here went from 289 presets and 52 recordings to 31 and 10, and the example project
  that ships from 67 to 41, sounding register for register the same.
- **The folder is read once and remembered.** A folder of hundreds of patch files is hundreds of
  opens at every start, so what was read is kept beside your settings as one file and read back
  from there: 369 presets read in 0.9 ms rather than 27.6. Add, remove or change anything in the
  folder and it is read properly again, so nothing you do in the file manager is missed.
- **From project** is where the browser lists what the open piece plays, beside the banks you
  have installed: its channels, what its notes and preset lanes name, and its kit. Open another
  piece, or start a new one, and it lists that piece's instead. A preset there is the piece's own
  copy, so renaming it or giving it an icon or tags changes the piece and nothing in your folder.

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
- **A scope**, switching between waveform and spectrum. Its right click menu sets the speed,
  how much time each lane shows from 10 ms to 160 ms, and the accuracy, whether a lane keeps one
  sample in four, one in two or every sample the chips make. A trace with more samples than its
  lane has pixels is drawn with every peak in it rather than only its first samples. Both
  settings are kept between sessions.
- **A hardware meter** for what the song is asking of the parts.
- **Warnings that link to their cause.** Click one and it selects the channel and the note. Among
  them are the two ways a piece is left sounding with nothing playing it: a note whose patch has a
  release rate of nought or one on a carrier, which is slower than anything a piece waits for, so
  its key off is never heard; and a square or the noise channel held past its last note by a level
  lane, over the silence that note ended on. A driver hides the first by always keying on again in
  time, and a piece that stops does not.
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
- **Follow playhead**, the last button in the editor's tools and an entry in the View menu, keeps
  the playhead in sight while a song plays. When it reaches the right edge of the playlist, the
  piano roll or the automation editor, the view turns a page so the playhead is back at the left,
  and a loop that sends it back scrolls back with it; in the tracker the cursor rides along with
  it. It is on to start with, it is kept between sessions, and it can be given a shortcut in the
  Keyboard preferences.
- **Declick**, in the Sound preferences and again in the export options, smooths the edges the
  chips would otherwise click on. A sample that stops away from the middle, cut by its note or
  ending there, returns to the middle over 1.5 ms instead of stepping there. An FM channel still
  sounding is let go at its quickest 4 ms before its next note keys it on, so the phase that key
  on resets starts about 50 dB down; a patch whose carriers attack slowly is left alone, because
  it swells legato from wherever the last note left it. Every write this adds is one a driver on
  the machine could make, so an export carries it too. Both start on, and what an export writes
  follows what you are listening to until you set the export's own row, the same way the output
  stage does. Switch it off for an export meant to hold exactly what a piece plays, such as a VGM
  read back register by register. The squares and the noise channel are left as they are: a
  square's output is a run of hard edges already, and a note starting or stopping adds no more to
  it than one of those edges does.
- **Stop stuck notes**, in the export options, ends what nothing is playing: a note whose patch
  cannot release is let go at the part's quickest rate where it ends, and the squares and the
  noise channel are written silent where the piece ends, which is what a level lane holding one
  past its last note would otherwise leave sounding. It is off to start with, because what a patch
  does is what the part does, and a piece whose notes all let go renders the same either way. The
  warnings say when a piece needs it.
- Three polyphony behaviours: **strict**, where a part that runs out of voices drops the note;
  **stealing**, where the oldest voice gives way; and **arpeggio**, where notes beyond the channel
  count are cycled through it.
- Velocity mapping and tuning per part.
- A monitoring fader with 20 dB of make up above unity, so a piece sitting in its headroom
  can still be listened to at the top of the scale. It is heard and never written: what
  makes an exported file loud is the normalising in the export panel.
- A MIDI keyboard plays the channel you have selected, on a chosen device, channel and velocity
  curve.
- **Audio device** in the Sound preferences sends the sound to any playback device the system
  has, or to the system default. The choice is kept by name, and a device that has gone falls back
  to the default.
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
| **MD Synth Preset File** and **MD Synth Preset Bank** | One preset or a whole bank, with every recording they play. They are added to your presets, and the piece you have open is left as it is |

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
- title, artist, album, year and comment, written into the file as tags along with the composer,
  genre and track number, all of them the project's own description, so changing one here changes
  it in the project
- **stems**, by track or by channel: one file per track or per part beside the mix, in a folder
  named after it

The FLAC encoder is this repository's own, written in Haxe from the format specification: LPC
prediction, partitioned Rice coding, stereo decorrelation and the MD5 signature, with no libFLAC
anywhere. Its files decode byte identical to the WAV written from the same samples, and its
signature matches libFLAC's.

The export is rendered offline at the rate asked for, not resampled from a 44.1 kHz render.

A stem by channel is that part rendered on its own, not the mix with everything else muted: the
events of every other part never reach the chips. A stem by track is named after the track and holds
only that track's notes and the channels they play on, with the automation clips on any track still
driving those channels, so it sounds the way the track does in the mix. Two tracks sharing a name
get numbered files rather than one over the other. Every stem takes the gain the mix worked out
rather than being normalised on its own, so the set of them sums back to the mix. Measured on a
three part piece, the stems sum to within -111 dB of the mix at worst and -138 dB once the output
stage has settled. Two channels keyed on the same sample share the chip's one write latch, so in a
stem that holds only one of them a note can start a sample away from where it started in the mix,
and there the sum is only within about -40 dB on a low note.

Only the parts the arrangement actually sounds get a stem, so a piece using four channels gives four
files rather than eleven, and only tracks that place notes get one, so a track holding nothing but
automation gives none. Track stems sum back to the mix wherever no two tracks play the same channel
at once.

### Video

**Export video** in the export menu opens a sheet of its own. It writes a WebM file of
oscilloscopes over the piece, with the mix underneath as Opus audio: a lane for every part the
piece uses, on a black background, with the part's name and a hairline between lanes and nothing
else. One to three parts stack in a column, up to eight sit two across, and more sit three
across. A part that is silent for a moment keeps a flat line. A bigger picture draws the lanes
bigger, text and lines included, rather than small with room around them.

The settings start at YouTube's recommended upload settings: 60 frames a second, a variable
bitrate at YouTube's figure for the size and frame rate, a key frame every half second, and stereo
audio at 384 kbit/s and 48 kHz. YouTube names no size, so a video starts at 2560 × 1440.

- **Video size:** 1280 × 720, 1920 × 1080, 2560 × 1440 or 3840 × 2160.
- **Frame rate:** 24, 25, 30, 48, 50 or 60 frames a second.
- **Scope:** Waveform or Spectrum.
- **Scope speed:** 10, 20, 40, 80 or 160 ms across a lane.
- **Scope accuracy:** Low, Medium or High, which keep one sample in four, one in two or every
  one.

  The three scope settings start at what the scope on screen is set to each time you open the
  sheet, until you change one of them there. Changing them on the sheet leaves the scope on
  screen alone.
- **Rate control:** VBR aims at an average bitrate, CBR holds the bitrate steady, CQ aims at a
  quality level with the bitrate as its ceiling, and Q aims at a quality level whatever it costs.
- **Video bitrate:** typed in kbit/s, or in megabits with an m after the number. Auto takes
  YouTube's recommended bitrate: 5000 kbit/s at 1280 × 720, 8000 at 1920 × 1080, 16000 at
  2560 × 1440 and 35000 at 3840 × 2160, or 7500, 12000, 24000 and 53000 at 48 frames a second and
  above. Where YouTube gives a range, Auto takes the low end. Q has no use for a bitrate, so it
  hides the field.
- **Quality level:** 0 to 63, for CQ and Q. Lower is better and bigger.
- **Encoder speed:** 5 to 9. Higher encodes faster and looks worse at the same bitrate. The VP9
  encoder is built for realtime encoding, and that build starts at 5, which is where a video
  starts too.
- **Keyframe interval:** a key frame at least every 0.5, 1, 2, 5 or 10 seconds. Shorter seeks
  faster and costs more.
- **Tune:** Screen suits the scope's flat ground and thin lines, and Default is VP9's ordinary
  tuning.
- **Chroma:** 4:4:4 keeps colour at full resolution and is where a video starts, because the
  scope's thin coloured lines lose more than half their colour at 4:2:0. 4:2:0 plays on more
  hardware video decoders.

Under VBR and CQ no frame is quantised coarser than level 40, which keeps the black ground from
flickering.
- **Audio bitrate**, channels, normalising, the output stage and the silence and fade times work
  as they do on the audio sheet.

The audio goes through the same render, output stage, fade and normalising an audio export does,
so what a video sounds like is exactly what an audio export with the same settings writes. VP9
and Opus are both compiled in, so there is nothing else to install.

### Register and note formats

- **VGM**, which reads back as the same register stream it was written from. A VGM holds the
  writes rather than the sound, so a player runs them through its own chip cores with no board
  after them, which is the chip alone output stage rather than a Mega Drive's.
- **XGM**, the format SGDK's driver plays. A kit exports each hit its keys pick, a hit stops where
  its note ends, and FM6 plays between samples, because the driver only takes channel six while a
  sample sounds. Timing is rounded to the driver's frame, a sixtieth of a second.
- **MIDI**, which reads back as the notes it was written from.
- **TFI**, one patch at a time.
- **`.mdpreset`** and **`.mdbank`**, one preset or a whole bank of them, with the recordings.

### The project

A zip packed with Deflate, or a folder, byte identical between runs. A zip's date field cannot
hold anything before 1980, so the written date is fixed at 1980 rather than being a real timestamp
that would make two saves of the same song differ.

---

## The project file

`.mdsyn`, a zip of JSON documents plus the samples. Every part of it is packed with Deflate, the
method every zip reader takes, so 7-Zip and the file manager of any desktop open it, and each part
carries the CRC32 of what it unpacks to, so a damaged file says so rather than opening wrong.
Packing takes a few milliseconds and loses nothing: the example project that ships is 265566
bytes unpacked and 26129 on disk, and one piece here went from 1119874 bytes to 55676 once it
also shed the presets it did not play. The suffix can be registered with the desktop so a double
click opens it, and unregistered again from preferences. The JSON reader and writer are
this repository's own, because a `Map` insertion order is preserved on some Haxe targets and not on
hxcpp, and a project that reorders itself between saves is not byte identical.

A project carries its own description: title, artist, composer, album, year, genre, track number and
comment, filled in under **Project info** in the file menu, and one step on the undo stack however
many change. Every audio export is tagged with them, including one started from the command line, a
VGM or XGM export writes the title, artist, album, year and comment into its tag block, and
importing one reads those back.

---

## Other

- **Portable mode.** A `portable.txt` beside the executable, which the portable archive ships,
  keeps settings, projects and presets in a `userdata` folder next to the program rather than in
  your account directory. The archive holds the program, SDL, the fonts, the icons and the banks
  that ship beside the program, and nothing else, 9 MB zipped. It leaves out the Japanese, Chinese and Korean fonts, which would be 36 MB of
  it on their own, and the program downloads the one a language needs when that language is
  picked, pinned to the same file the installer ships.
- **A start that fails says why.** A window that will not open, drawing that will not start, and
  fonts that are missing or will not read each raise a box saying what went wrong and what to do,
  rather than the program closing with nothing on screen.
- **It saves on its own** every five or ten minutes, or never, and only once something has changed.
  A song that was never saved by hand goes to a recovery file rather than nowhere.
- **Backups**, kept for as long as you set.
- **An updater that asks first.** It checks the releases page, and when there is something newer it
  says which version you have and which is offered, and gives you download, not now, or stop
  asking. Nothing reaches the network until you say so. It offers a portable copy an archive and an
  installed copy an installer, and for the right architecture, then replaces the files and starts
  the new copy. What it downloads is checked against the `SHA256SUMS` the release publishes before
  anything is unpacked, and a file that does not match is deleted rather than run. That says the
  download arrived whole, not that it is genuine: the Sigstore signature beside each file is what
  answers that, and checking one of those is still something you do yourself.
- **An installer that knows what is already there.** Running it over an existing copy says which
  version is installed and which one it carries, and asks before replacing it, whether that is an
  update, the same version again, or a downgrade.
- **Terms before anything is installed.** The installer shows its terms of use and the MIT licence
  first, and installs nothing until you accept them. They say plainly that MD Synth DAW is free, so
  anyone who charged for a copy scammed you, where the official downloads are, and what the
  application connects to.
- **You choose where it goes.** The installer always shows the folder page, on an update too,
  with the last folder already filled in and how much disk space the install takes. Uninstalling
  removes the whole install folder, so if you pick a folder that already has other files in it,
  the installer makes a folder of its own inside it and tells you.
- **You choose which fonts it installs.** Japanese, Simplified Chinese and Korean each need a font
  of their own, 36 MB together, so the installer lists them as options, all three ticked. Clear one
  and its font is left out, and running the installer again without it deletes the font an earlier
  install left, along with any copy MD Synth DAW downloaded for that language since. English and
  every other language need no extra font and are always installed.
- **A language whose font is missing still shows up.** The first run sheet and the preferences list
  it with the size of its font. Picking it downloads the font from the commit the build pins,
  checks the SHA-256 before the file is used, and switches language once it lands. A download that
  fails or does not match is deleted and says so. A language saved in the settings whose font has
  gone since starts the application in English rather than drawing nothing.
- **A translatable interface.** Every string it shows comes from one table rather than from
  the code, so adding a language is a file rather than a change to the program. Hardware and
  format names are not in the table: `FM3`, `$4C`, `TL` and `bpm` stay as the documentation
  writes them in every language. Which languages ship, and how each was translated, is in
  the README, and the sheet that asks for one on the first run says whether the language
  picked was written by a person or translated by a machine.
- **A page on the console's limits**, in the help menu: five FM channels once the sample channel
  is in use, one LFO, no pan pot, volume in steps, the squares' lowest note, channel three's four
  notes, what samples cost, one note per channel and a release some drivers never let sound. Each
  comes with the way the music of the time worked around it, with Sonic the Hedgehog as the
  example.
- **Themes, typefaces, interface density** and reduced motion, which follows the desktop setting
  unless you override it.
- **Text size** from 90% to 150%, on its own, so the text can grow without the rows and controls
  growing with it.
- **Eight themes**: Midnight, Rack and Slate, Material and Fluent in dark and in light, and Pastel.
  **Part colours** can be the standard set or one told apart with the common forms of colour
  blindness, with the FM parts in warm colours and the square parts in cool ones, and on a light
  theme either set is drawn deep enough to read on the lighter ground.
- **The pointer takes a shape over what it is on**: a double arrow on a splitter, on the line
  between two lanes and on either end of a note or a clip, an I-beam in a field, and the four
  pointed arrow with the pan tool in hand.
- **Every control says what it does** when you hover it: the transport fields, the rulers and
  track headers, the dials, the monitors, every preference and every export setting. Where a
  click does more than one thing, a second line says what the right click or the wheel does.
- **One instance.** Opening a second project hands it to the copy already running, by a double
  click or from a terminal, and that copy comes to the front and opens it, asking first about
  unsaved work the way any open does. Starting a second copy with nothing to open brings the first
  one forward. A path with letters outside ASCII in it opens the same way.
- **Discord presence**, on by default and showing the piece and what the transport is doing,
  speaking Discord's local IPC directly rather than through an SDK. Preferences can cut it down to
  the application's name alone or turn it off.
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
