# Console Tricks

`console-tricks.mdsyn` is a project of 19 small examples, each showing a way around something the
Mega Drive's two sound chips can't do on their own. Open it in MD Synth DAW and play it from the
start, or solo one track at a time.

Each example is **one track holding one four bar pattern**, and the tracks run top to bottom in the
order below with a bar of rest between examples. At 120 bpm every example is 8 seconds long and a new
one starts every 10 seconds. Most of them play the plain way first and the trick after it inside the
same pattern, so you can hear the difference without switching anything.

**Help → Console limits** in the app lists the limits these examples work around.

| # | Example | Starts at | Channels |
| --- | --- | --- | --- |
| 1 | [Vibrato](#1-vibrato) | 0:00 | FM4 |
| 2 | [Bends and slides](#2-bends-and-slides) | 0:10 | FM4 |
| 3 | [Tremolo and gate](#3-tremolo-and-gate) | 0:20 | FM4 |
| 4 | [Distortion](#4-distortion) | 0:30 | FM1 |
| 5 | [Filter sweep](#5-filter-sweep) | 0:40 | FM1 |
| 6 | [Patch morphing](#6-patch-morphing) | 0:50 | FM4 |
| 7 | [Preset swapping](#7-preset-swapping) | 1:00 | FM3 |
| 8 | [Manual preset swapping](#8-manual-preset-swapping) | 1:10 | FM4 |
| 9 | [Chords](#9-chords) | 1:20 | FM4, FM5, PSG1, PSG2 |
| 10 | [Arpeggios](#10-arpeggios) | 1:30 | FM4, PSG1 |
| 11 | [Unison detune](#11-unison-detune) | 1:40 | FM4, FM5 |
| 12 | [Echo](#12-echo) | 1:50 | FM4, FM5, PSG3 |
| 13 | [Simulated panning](#13-simulated-panning) | 2:00 | FM4, FM5 |
| 14 | [Sidechain](#14-sidechain) | 2:10 | FM4, FM5, PSG1, PSG2, DAC |
| 15 | [Square swells](#15-square-swells) | 2:20 | PSG1, PSG2, PSG3, noise |
| 16 | [FM drums](#16-fm-drums) | 2:30 | FM1, FM2, FM3, noise |
| 17 | [Pitched noise](#17-pitched-noise) | 2:40 | PSG3, noise |
| 18 | [Sharing channel six](#18-sharing-channel-six) | 2:50 | FM6, DAC |
| 19 | [Sample stutter](#19-sample-stutter) | 3:00 | DAC |

Every sound in the project is a preset saved inside it, named for what it does, so you can open
any of them in the instrument editor and copy them into your own songs. The drums are the Drum Kit
that ships with the app.

---

## Before you start

Almost every trick here is an automation lane in the piano roll. A few things about lanes are worth
knowing first, because the examples lean on them.

### Lane names

| Channel | Lanes |
| --- | --- |
| FM | `TL 1` to `TL 4`, `FREQ`, `SIDES`, `DT MUL 1` to `4`, `KS AR`, `AM D1R`, `D2R`, `D1L RR`, `SSG`, `FB ALG`, `PRESET` |
| Squares | `LEVEL`, `PERIOD`, `PRESET` |
| Noise | `LEVEL`, `NOISE`, `PRESET` |

Positions in this guide are in ticks, as the point inspector's `AT` shows them: 96 ticks to a beat,
384 to a bar.

### Shapes

A point's shape says how the value travels to the next point: Hold, Linear, Curve, Smooth, Stairs,
Smooth stairs, Pulse, Wave or Half sine. Stairs, Pulse and Wave repeat, and you choose how many
times (2, 3, 4, 6, 8, 12 or 16) from the point's right-click menu. **A Wave or Pulse point swings
between its own value and the next point's value**, so a vibrato is one Wave point at the bottom of
the swing and one point after it at the top.

### Registers that hold two settings

Several FM lanes write one register that holds two settings, so the value you enter is both packed
together:

| Lane | Value |
| --- | --- |
| `FB ALG` | feedback × 8 + algorithm |
| `DT MUL` | detune × 16 + multiple |
| `KS AR` | rate scaling × 64 + attack rate |
| `AM D1R` | 128 if the LFO's tremolo reaches the operator, + first decay rate |
| `D1L RR` | sustain level × 16 + release rate |
| `SIDES` | 128 for left + 64 for right + tremolo depth × 16 + vibrato depth |

So `FB ALG` 61 is feedback 7 on algorithm 5, and `SIDES` 197 is both speakers with vibrato depth 5.

### Which operators you hear

A `TL` lane on a **carrier** changes the volume. On a **modulator** it changes the tone, because it
sets how hard that operator bends the ones it feeds.

| Algorithm | Carriers |
| --- | --- |
| 0 to 3 | 4 |
| 4 | 2 and 4 |
| 5 and 6 | 2, 3 and 4 |
| 7 | all four |

### Pitch in `FREQ` and `PERIOD`

`FREQ` moves an FM note in F number steps, and how many steps make a semitone depends on the note.
Take the note's F number from this table and work out `F × (2^(semitones ÷ 12) − 1)`:

| C | C♯ | D | D♯ | E | F | F♯ | G | G♯ | A | A♯ | B |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 644 | 682 | 723 | 766 | 811 | 859 | 910 | 965 | 1022 | 1083 | 1147 | 1215 |

An octave down is minus half the F number, and an octave up is plus the whole F number. The table
is the same in every octave. For example, 4 semitones up from any C is 644 × 0.26 = 167.

`PERIOD` moves a square in period steps instead, and it runs the other way: a bigger number is a
lower pitch.

### Two rules worth knowing

1. **A lane holds its value from one note to the next,** and a note before a lane's first point
   uses that first point's value. Put a point at the start of the pattern holding the normal value,
   as every example here does, and one point is enough for every note after it.
2. **A `LEVEL` lane on a square or the noise channel replaces the instrument's envelope** for that
   channel in the whole pattern. That is why Square swells keeps its envelope examples and its lane
   examples on different squares.

---

## 1. Vibrato

**The limit.** The YM2612 has one LFO for all six channels, so every channel that uses it wobbles at
the same speed. Its speed is a setting for the whole song: the **LFO** field in the transport bar
switches it on and picks one of its eight rates. This project uses 6.21 Hz. A new project starts
with the LFO off.

**The trick.** Draw the vibrato in the `FREQ` lane instead. It can have any speed and depth, it can
start late, and every channel can have its own.

**In the pattern** (FM4, preset *Plain lead*, one A4 per bar):

- **Bar 1:** no vibrato.
- **Bar 2:** the chip's LFO. `SIDES` is 197, both speakers with vibrato depth 5, about ±20 cents.
- **Bar 3:** `FREQ` has a Wave point at −16 with 12 repeats and a point at +16 at the end of the
  note. At A4, 16 steps is about 25 cents, and 12 repeats in a bar at 120 bpm is 6 Hz.
- **Bar 4:** a delayed vibrato. `FREQ` stays at 0 for the first 120 ticks, then Linear points six to
  a beat swing above and below, each a little further out than the last.

Measured on the render, the pitch doesn't move in bar 1, swings about 31 cents in bar 2 and 43 in
bar 3, and in bar 4 swings 6 cents in the first half and 37 in the second.

## 2. Bends and slides

**The limit.** A note's pitch is fixed when it starts, and the chip has no portamento.

**The trick.** Offset the pitch with `FREQ` while the note holds, and ramp between the offsets.

**In the pattern** (FM4, preset *Brass*):

- **Bar 1:** C5 starts 2 semitones flat, `FREQ` −70 with a Curve point, and reaches 0 an eighth
  later. D5 then holds until tick 300 and falls off with a Smooth point down to −181, 5 semitones.
- **Bar 2:** G5 holds for a beat, then dives an octave with a Smooth point down to −482, half its F
  number.
- **Bar 3:** C5, E5, G5 and C6 as four notes, each scooped up from a semitone under over a
  sixteenth: `FREQ` starts at −36, −46, −54 and −36 and ramps to 0. Every note is a new key on.
- **Bar 4:** the same four notes tied. Select them, right-click and choose **Tie**. There is only
  one key on, so the line slides from note to note like legato while each scoop still bends in.

## 3. Tremolo and gate

**The limit.** The chip's tremolo also comes from the single LFO, at one speed for everything, and
there is no volume envelope you can sync to the tempo.

**The trick.** Draw the volume on the carriers' `TL` lanes with a repeating shape.

**In the pattern** (FM4, preset *Tremolo organ*, algorithm 4, so operators 2 and 4 are the
carriers):

- **Bar 1:** the chip's own tremolo. The preset has tremolo switched on for both carriers, and
  `SIDES` 240 sets tremolo depth 3, about 12 dB.
- **Bar 2:** `TL 2` and `TL 4` each have a Wave point at 0 with 8 repeats and a point at 14 after it,
  so the note dips about 10 dB eight times a bar, locked to the tempo.
- **Bar 3:** the same lanes with a Pulse point between 0 and 60: a gate that opens and closes every
  sixteenth.
- **Bar 4:** Hold points on every sixteenth, open (0) or shut (60), for a gate rhythm you draw
  yourself.

## 4. Distortion

**The limit.** There is no distortion effect. What the chip has instead is feedback on operator 1
and operators that bend each other.

**The trick.** Turn up the modulator's level and the feedback. The preset *Drive guitar* uses
algorithm 5, where operator 1 feeds carriers on multiples 1, 2 and 3, so one note is already a power
chord.

**In the pattern** (FM1, the same riff every bar):

- **Bar 1:** clean. `TL 1` is +40, which keeps the modulator 40 steps quieter than the preset has
  it, and `FB ALG` is 5, feedback 0.
- **Bar 2:** `TL 1` runs from +40 down to 0 across the bar. More modulation is more grit.
- **Bar 3:** `FB ALG` climbs one feedback step every eighth: 5, 13, 21, 29, 37, 45, 53 and 61.
  Feedback only makes a difference once operator 1 is loud enough to be heard through the carriers,
  which is why bar 2 turns it up first.
- **Bar 4:** both at once, `FB ALG` 53 (feedback 6) and `TL 1` at −8.

Measured, the energy above 2 kHz goes from 48 dB under the whole sound in bar 1 to about 18 dB under
it in bar 4.

## 5. Filter sweep

**The limit.** There is no filter.

**The trick.** A modulator's level decides how bright an FM sound is, so sweeping it works like a
filter.

**In the pattern** (FM1, preset *Sweep bass*, algorithm 3, where operators 2 and 3 both feed the
carrier):

- **Bars 1 and 2:** `TL 2` and `TL 3` run Linear from +50 (dark) to 0 (open) across both bars.
- **Bar 3:** back from 0 to +50.
- **Bar 4:** a wah on every beat, +50 on the beat and 0 on the offbeat.

The line is sixteenth notes, and each new note starts at the level the lanes hold at that moment, so
the sweep runs smoothly across all of them.

## 6. Patch morphing

**The limit.** A preset is a fixed sound.

**The trick.** Every register has a lane, so any single setting can change while the song plays.

**In the pattern** (FM4, preset *Morph bell*, algorithm 4):

- **Bar 1:** `DT MUL 1` steps through multiples 1 to 8, one per eighth note.
- **Bar 2:** `FB ALG` changes on every beat: 28, 24, 29 and 31 are algorithms 4, 0, 5 and 7, all
  with feedback 3.
- **Bar 3:** `KS AR 2` and `KS AR 4` set the carriers' attack to 8, 10, 13 and 31, one per note. The
  first swells without ever reaching full level, the next two take about 275 ms and 125 ms, and the
  last is instant.
- **Bar 4:** `D1L RR 2` and `D1L RR 4` set the release to 15, 8, 4 and 1 (values 79, 72, 68 and 65)
  on short stabs, so the tails grow longer.

**A slow attack only sounds slow from silence.** The chip starts a new attack from wherever the last
note's release has got to, so a note played straight after another comes in loud whatever its
attack rate. That is why bar 3's notes are short with rests between them, and why `D1L RR` is set to
a fast release from the last note of bar 2.

## 7. Preset swapping

**The limit.** Six FM channels, or five with drum samples, never feel like enough.

**The trick.** A `PRESET` lane makes one channel play several instruments in turn. Right-click a
preset and choose **Switch at playhead** to add a point. From each point on, every note loads that
whole preset at its key on.

**In the pattern** (FM3, the same riff in bars 1 to 3):

- **Bar 1:** *FM bass*.
- **Bar 2:** *Organ*.
- **Bar 3:** *Brass*.
- **Bar 4:** a `PRESET` point on every note, *FM kick* on beats 1 and 3 and *FM bass* on the rest, so
  one channel plays the kick and the bass line. The kicks also get a `FREQ` point at +900 curving to
  0 over 30 ticks, and the bass notes a point at 0.

## 8. Manual preset swapping

**The limit.** A `PRESET` point loads the whole preset, and only when a note starts.

**The trick.** When two sounds differ in only a few registers, change just those registers with
their own lanes. That is fewer writes to the chip, and it can happen in the middle of a note. Sound
drivers of the time did the same.

**In the pattern** (FM4, preset *Plain lead*, the same phrase in bars 1 to 3):

- **Bar 1:** the preset as it is. Every lane starts with a point holding the preset's own value:
  `DT MUL 1` 1, `DT MUL 3` 2, `AM D1R 2` and `4` 1, `D1L RR 2` and `4` 23, `FB ALG` 28 and `TL 1` 0.
- **Bar 2:** hollow. `DT MUL 1` becomes 3 and `DT MUL 3` becomes 5.
- **Bar 3:** plucked. The multiples go back, `AM D1R 2` and `4` become 12, and `D1L RR 2` and `4`
  become 151, sustain level 9 with the same release.
- **Bar 4:** the plain preset again on one held G5. Halfway through, on beat 3, `FB ALG` becomes 61
  (feedback 7, algorithm 5) and `TL 1` drops to −12, and the note turns into a buzz without starting
  again. A `PRESET` lane can't do that.

## 9. Chords

**The limit.** Each channel plays one note at a time.

**The trick.** Spread a chord over several channels, or build one into a single channel with
operator multiples.

**In the pattern:**

- **Bar 1:** C major over four channels. C4 and E4 on FM4 and FM5, G4 and C5 on PSG1 and PSG2.
- **Bar 2:** A minor on FM4 alone. The preset *Minor chord* is algorithm 7 with operators on
  multiples 10, 12 and 15 and operator 4 silent. Those three ratios make a minor triad, so the note
  F1 sounds A4, C5 and E5.
- **Bar 3:** F major on FM4 alone. *Major chord* uses multiples 4, 5 and 6 for a major triad, so F2
  sounds F4, A4 and C5.
- **Bar 4:** a G power chord on FM4 alone. *Power chord* uses multiples 1, 2 and 3 with feedback, so
  G2 sounds G2, G3 and D4.

To play these presets: for multiples 4, 5 and 6, play the root two octaves down. For 10, 12 and 15,
play the note 40 semitones under the root (three octaves and a major third). These chords are in
just intonation, so the third of the major chord and the outer notes of the minor one sit about 12
to 14 cents flat of the piano, which makes them sound very still. Measured, bar 2's peaks are at
436, 524 and 655 Hz and bar 3's at 349, 436 and 524 Hz.

## 10. Arpeggios

**The limit.** Also one note per channel. The sound of the era's chords is a fast arpeggio.

**The trick.** Play the arpeggio as fast notes, or hold one note and step its pitch with `FREQ` so
there is no new key on at all.

**In the pattern:**

- **Bar 1:** C major as thirty second notes on FM4 (preset *Organ*). Every note is a key on and ends
  a sixty fourth early, so it chops.
- **Bar 2:** one A4 held on FM4, with Hold points every 8 ticks on `FREQ` cycling 0, 205 and 540,
  which are A, C and E. It's smooth, because nothing restarts.
- **Bar 3:** one F4 held, stepping 0, 223, 428 and 859 every 12 ticks: F, A, C and the F above.
- **Bar 4:** G major as thirty second notes on PSG1 (preset *Square lead*). A square has no key on to
  click, so fast notes are clean there.

## 11. Unison detune

**The limit.** One channel is one oscillator, and the chip has no chorus.

**The trick.** Play the same notes on two channels, one panned left and one right, pulled a few F
number steps apart.

**In the pattern** (preset *Plain lead*):

- **Bars 1 and 2:** the melody on FM4 alone.
- **Bars 3 and 4:** FM4 panned left with `FREQ` at −3, and FM5 panned right with the same notes and
  `FREQ` at +3. The small difference beats slowly and spreads the sound out.

Measured, the left and right outputs have a correlation of 1.0 in bars 1 and 2 and 0.08 in bars 3
and 4.

## 12. Echo

**The limit.** There is no delay effect.

**The trick.** Play the echo yourself: in the gaps of the same channel, or on a spare channel.

**In the pattern** (preset *FM pluck*):

- **Bar 1:** dry, on FM4.
- **Bar 2:** the echo in the same channel. After each note, a quieter copy (velocity 56) an eighth
  later fills the gap before the next one.
- **Bars 3 and 4:** a longer phrase on FM4 panned left. FM5, panned right, plays the same notes a
  dotted eighth (72 ticks) later at velocity 72, and PSG3 plays them a dotted quarter (144 ticks)
  later on *Square pluck*.

## 13. Simulated panning

**The limit.** An FM channel is left, right or both, with nothing in between. The squares and the
noise channel have no panning at all on the Mega Drive; they always sound in the middle.

**The trick.** Move a sound between the three positions over time, or play it on two channels, one
on each side, and set how loud each one is.

**In the pattern** (preset *Soft lead*, algorithm 3, so operator 4 is the only carrier):

- **Bar 1:** `SIDES` changes every beat: 128 (left), 192 (both), 64 (right), 192 (both).
- **Bar 2:** one held note with `SIDES` swapping between left and right every sixteenth.
- **Bars 3 and 4:** the same notes on FM4 (left) and FM5 (right). `TL 4` on each crossfades over
  five Linear points about half a bar apart: FM4 goes 0, 0, 0, 12, 60 and FM5 goes 60, 12, 0, 0, 0.
  One TL step is 0.75 dB, so 12 is 9 dB quieter and 60 is practically silent. The sound travels
  from the left through the middle to the right.

Measured, bar 1 is 29 dB left, even, 22 dB right, even. Bars 3 and 4 move 15 dB left, 3 dB left,
4 dB right and 17 dB right.

## 14. Sidechain

**The limit.** There is no compressor, and nothing can hear the kick.

**The trick.** Draw the ducking yourself: dip the pad on every kick and bring it back before the
next one.

**In the pattern** (the Drum Kit's kick on every beat, preset *Pad* on FM4 and FM5, *Square flat* on
PSG1 and PSG2):

- **Bars 1 and 2:** no ducking.
- **Bars 3 and 4:** on every beat, `TL 2` and `TL 4` on FM4 and FM5 get a Curve point at 30 that
  returns to 0 by tick 84, seven eighths of the beat. The squares' `LEVEL` lanes do the same from 8.

Measured above 400 Hz, where the kick hardly reaches, bar 2 holds steady and bar 4 dips about 11 dB
on every beat.

## 15. Square swells

**The limit.** The squares have no attack, decay or release, only a volume in 16 steps.

**The trick.** Either write the volume steps into the instrument's envelope, or draw them on a
`LEVEL` lane.

**In the pattern:**

- **Bar 1:** *Square pluck* on PSG1 and PSG2. Its envelope steps 0, 2, 4 and so on up to 15 decay the
  note.
- **Bar 2:** *Slow square*. Its envelope steps from 15 down to 3, 6 frames a step, so the chord
  swells in over about a second.
- **Bar 3:** a note on PSG3 with a `LEVEL` lane running Linear from 15 to 0 over the bar. Unlike an
  envelope, a lane is exactly one bar long at any tempo.
- **Bar 4:** PSG3 fades out with a Curve from 0 to 15, while the noise channel plays *Cymbal swell*
  with its `LEVEL` curving from 15 to 0: a reverse cymbal.

Rule 2 is why bars 1 and 2 use PSG1 and PSG2 and the lanes are on PSG3 and the noise channel.

## 16. FM drums

**The limit.** Drum samples take FM6, and the DAC plays one sample at a time.

**The trick.** Make the drums from FM, with a fast pitch dive, and layer the noise channel where you
need a rattle.

**In the pattern:**

- **Kick** on FM1, preset *FM kick*: algorithm 0, operator 3 clicking into a sine on operator 4 that
  decays to silence. `FREQ` jumps to +900 on every hit and curves to 0 over 30 ticks.
- **Snare** on FM2, preset *FM snare*: operator 1 on multiple 15 with feedback 7 gives a noisy
  carrier and operator 4 a short body, with `FREQ` +200 falling to 0. The noise channel plays *Noise
  snare* on the same beats.
- **Hats** on the noise channel between the snares.
- **Toms** on FM3 in bar 4, preset *FM tom*, each diving from +320.

The DAC stays free, and so does FM6.

## 17. Pitched noise

**The limit.** The noise channel has three fixed speeds, so on its own it can't play a tune.

**The trick.** Two of the noise modes follow the third square's pitch instead. Silence the third
square and use it only to set that pitch. In the `NOISE` lane, 3 is periodic noise and 7 is white
noise, both following the third square, and the Noise dial in the instrument editor takes the same
numbers.

**In the pattern:**

- **Bars 1 and 2:** a bass line. The noise channel plays *Periodic bass* (periodic, following the
  square) and PSG3 plays *Tone off*, an envelope held at 15, on notes 36 semitones above the bass.
  **Periodic noise sounds three octaves under the third square's note.** Measured, E♭ plays at
  77.5 Hz and G at 97.5 Hz.
- **Bar 3:** *Tuned noise* (white, following the square) over one held C6 on PSG3, with a Wave point
  on `PERIOD` swinging between 0 and +400 twice: a wind sweep.
- **Bar 4:** *Tuned hit* on every eighth over a falling line on PSG3.

The price is PSG3, which can't play anything else while it steers the noise.

## 18. Sharing channel six

**The limit.** The DAC and FM6 are the same channel.

**The trick.** The DAC only takes FM6 while a sample is actually sounding. Keep the drum notes short
and FM6 can play in the gaps between them.

**In the pattern:**

- **Bars 1 to 3:** kick and snare as eighth notes on every beat. FM6 plays a bass note (preset *FM
  bass*) on every offbeat, ending before the next drum starts.
- **Bar 4:** a kick a sixteenth long, then a run of sixteenths on FM6, a snare, one more FM6 note,
  and a snare roll.

If an FM6 note overlaps a sample note, the app warns you, because the sample will cut it off.
Measured, the offbeat bass notes sound at their pitches, 77.8 Hz and 97.9 Hz among them.

## 19. Sample stutter

**The limit.** The DAC plays a sample at the rate it was recorded, with no pitch or volume control.

**The trick.** Use note lengths. A sample stops where its note stops, and every new note starts the
sample again from the beginning.

**In the pattern** (Drum Kit):

- **Bar 1:** kick, snare and crash on long notes, so each plays to its end.
- **Bar 2:** kick and snare, then 16 snare notes a thirty second long each: a roll that restarts the
  snare every time.
- **Bar 3:** the crash as eight notes, each 12 ticks long on a sixteenth grid, so it stutters on its
  attack. Then the ride on every eighth, cut to a sixteenth, which gates it.
- **Bar 4:** a snare on every beat, a quarter, an eighth, a sixteenth and a thirty second long. The
  shorter the note, the tighter the snare.
