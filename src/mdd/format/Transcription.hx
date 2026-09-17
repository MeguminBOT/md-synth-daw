/*
	MD Synth DAW
	https://github.com/MeguminBOT/md-synth-daw

	MIT License

	Copyright (c) 2026 MeguminBOT and the md-synth-daw contributors

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.

	SPDX-License-Identifier: MIT
*/
package mdd.format;

import haxe.ds.Vector;
import mdd.chip.Sn76489;
import mdd.chip.Ym2612;
import mdd.play.Stream;
import mdd.song.Clip;
import mdd.song.Instrument;
import mdd.song.Note;
import mdd.song.Part;
import mdd.song.Patch;
import mdd.song.Pattern;
import mdd.song.Sample;
import mdd.song.Song;
import mdd.song.Tempo;
import mdd.song.Track;

@:unreflective

/**
	Turns a register stream back into a song: notes, patches, square envelopes, samples
	and automation.

	Reading the file is `Vgm` or `Xgm` and gives back exactly what was written. This is
	the separate step that decides what those writes meant, and it is separate because
	a guess must never reach the register stream.

	Three things it has to get right. A key on is read as the nearest semitone, and
	writing that semitone back gives a frequency word one or two units from a game's own
	table, so the exact word is recorded beside the note wherever the two differ. A note
	model cannot hold what happens between key ons, so every frequency the driver
	writes while a note sounds becomes an automation lane rather than being thrown
	away. And channel three's second mode is written to by files that never use it, so a
	first write of zero is ignored rather than growing three lanes that write nothing.
**/
final class Transcription {
	/**
		Operator slot to register offset. The part lays operators out 1, 3, 2, 4.
	**/
	static final GROUP:Vector<Int> = Vector.fromArrayCopy([0, 2, 1, 3]);

	/**
		The song that was read out of the stream.
	**/
	public var song(default, null):Song;

	/**
		How many notes were placed.
	**/
	public var notes(default, null):Int = 0;

	/**
		The largest disagreement between a written frequency word and the note it was read
		as, in cents. It is a fraction of a cent in practice, and it is why the exact word
		is kept.
	**/
	public var worstCents(default, null):Float = 0;

	/**
		How many notes did not land on the guessed grid.
	**/
	public var offGrid(default, null):Int = 0;

	/**
		How many did.
	**/
	public var onGrid(default, null):Int = 0;

	/**
		How many key ons were seen.
	**/
	public var sounded(default, null):Int = 0;

	/**
		The tempo that was guessed.
	**/
	public var beats(default, null):Float = 150;

	final shadow:Vector<Int> = new Vector<Int>(512);
	final keyed:Vector<Bool> = new Vector<Bool>(6);
	final startedAt:Vector<Int> = new Vector<Int>(6);
	final startedOn:Vector<Int> = new Vector<Int>(6);
	final keyedLevel:Vector<Int> = new Vector<Int>(24);
	final everKeyed:Vector<Bool> = new Vector<Bool>(6);
	final everSquared:Vector<Bool> = new Vector<Bool>(4);
	final startedWith:Vector<Int> = new Vector<Int>(6);
	final tying:Vector<Bool> = new Vector<Bool>(6);
	final started:Vector<Bool> = new Vector<Bool>(6);

	final psgPeriod:Vector<Int> = new Vector<Int>(4);
	final psgLevel:Vector<Int> = new Vector<Int>(4);
	final psgFrom:Vector<Int> = new Vector<Int>(4);
	final psgNote:Vector<Int> = new Vector<Int>(4);

	/**
		How many samples one square envelope step lasts.
	**/
	static inline final ENVELOPE_TICKS = 735;

	/**
		The most steps a recovered square envelope may have.
	**/
	static inline final ENVELOPE_STEPS = 96;

	final psgWhen:Array<Array<Int>> = [[], [], [], []];
	final psgHeld:Array<Array<Int>> = [[], [], [], []];
	final shapes:Array<Int> = [];

	var latched:Int = 0;
	var noiseMode:Int = -1;
	var dacOn:Bool = false;
	var dacHead:Int = -1;
	var dacLast:Int = 0;

	static inline final PER_TICK = 1;

	/**
		How long a gap between converter writes counts as the sample ending rather than as
		a pause inside it.
	**/
	static inline final DAC_GAP = 2205;

	/**
		How long a gap counts as a pause that must be left out of the rate measurement. A
		run measured end to end reads far slower than it was written, because the driver
		stops writing during a rest, and playing it back at that mean stretches everything
		after the pause.
	**/
	static inline final DAC_PAUSE = 256;

	/**
		The fewest bytes a run must have to count as a sample at all.
	**/
	static inline final DAC_LEAST = 128;
	static inline final STALL_REACH = 48;
	static inline final STEADY = 32;
	static inline final STEADY_TURN = 1.3;
	static inline final DAC_ROOM = 1 << 22;

	/**
		The key the first recording the converter takes sits on, the next one a
		semitone above it, and so on, wrapping once every key has one.

		A recording is chosen by the instrument the note carries rather than by the
		key, so the key changes nothing about what is heard. It is what the editor
		lays the note out on, and a file whose hits all sit on one key is a file
		whose drums are drawn as a single row.

		A few files carry more recordings than there are keys, and those wrap rather
		than piling onto the last one: sharing a row is only a loss of the drawing,
		and sharing it with a hundred others is a worse one.
	**/
	static inline final DAC_ROOT = 60;

	/**
		How many keys there are to put a recording on.
	**/
	static inline final KEYS = 128;
	static inline final DAC_QUIET = 4;
	static inline final DAC_SLIP = 8;
	static inline final DAC_APART = 6.0;

	/**
		How many times longer one recording may be than another and still be called
		the same sound.
	**/
	static inline final DAC_STRETCH = 2;
	static inline final DAC_BLOCK = 32;
	static inline final DAC_STEP = 800;

	final dacBytes:Array<Int> = [];
	final dacWhen:Array<Int> = [];
	final dacTake:Array<Int> = [];
	final kits:Array<Int> = [];
	final prints:Array<Vector<Float>> = [];
	var dacHeld:Int = 0;

	var perTick:Float = 183.75;
	var pattern:Pattern;

	/**
		Private: use `of`.
	**/
	function new() {}

	/**
		Reads a register stream into a song.

		@param stream The writes to read.
		@param rate The rate their positions are in.
		@param name What to call the song.
		@return The transcription, with the song in `song` and the counts beside it.
	**/
	public static function of(stream:Stream, rate:Int, name:String):Transcription {
		final made = new Transcription();
		made.take(stream, rate, name);
		return made;
	}

	/**
		@param rate A sample rate.
		@return A tempo to fall back on where none can be found.
	**/
	static function tempoFor(rate:Int):Float {
		return rate == 50 ? 125 : 150;
	}

	/**
		Walks every write, then splits what was found into patterns and tracks.

		@param stream The writes to read.
		@param rate The rate their positions are in.
		@param name What to call the song.
	**/
	function take(stream:Stream, rate:Int, name:String):Void {
		beats = Pulse.of(stream, rate, tempoFor(rate));

		final ppqn = Math.round(Tempo.TICKS * 60.0 / (beats * PER_TICK));

		song = new Song(name, ppqn, beats);
		perTick = Tempo.TICKS * 60.0 / (beats * ppqn);

		for (i in 0...shadow.length) shadow[i] = 0;

		for (half in 0...2) {
			for (at in 0x40...0x50) shadow[(half << 8) | at] = 0x7F;
		}

		for (i in 0...6) {
			keyed[i] = false;
			startedAt[i] = 0;
			startedOn[i] = 60;
			everKeyed[i] = false;
			for (slot in 0...4) keyedLevel[i * 4 + slot] = 0;
			startedWith[i] = -1;
			tying[i] = false;
			started[i] = false;
		}

		for (i in 0...levels.length) levels[i] = -1;
		for (i in 0...envelopes.length) envelopes[i] = -1;
		for (i in 0...stereos.length) stereos[i] = -1;
		for (i in 0...wirings.length) wirings[i] = -1;
		for (i in 0...tunes.length) tunes[i] = -1;
		for (i in 0...operators.length) operators[i] = -1;

		for (i in 0...4) {
			psgPeriod[i] = 0;
			psgLevel[i] = 15;
			psgFrom[i] = -1;
			psgNote[i] = 60;
			everSquared[i] = false;
		}


		final last = stream.count == 0 ? 0 : stream.tickAt(stream.count - 1);
		pattern = song.add(new Pattern(name, ticked(last) + song.tempo.ppqn));

		final track = song.track(new Track("imported"));
		track.add(new Clip(0, 0, pattern.length));

		var half = 0;
		var address = -1;

		for (index in 0...stream.count) {
			final at = stream.tickAt(index);
			final port = stream.portAt(index);
			final value = stream.valueAt(index);

			if (stream.kindAt(index) == Stream.PSG) {
				square(at, value);
				continue;
			}

			if ((port & 1) == 0) {
				half = (port >> 1) & 1;
				address = value;
				continue;
			}

			if (address < 0) continue;

			shadow[(half << 8) | address] = value;
			applied(at, half, address, value);
		}

		close(last);
		parted();
		session();
		mdd.song.Shipped.into(song);

		settle();
	}

	/**
		@param sample A sample position.
		@return The tick it falls on, at the guessed tempo.
	**/
	inline function ticked(sample:Int):Int {
		return Math.round(sample / perTick);
	}

	/**
		Follows one FM register write and decides what it means.

		@param at The sample the write happens at.
		@param half Which half of the register file, 0 or 1.
		@param address The register address within that half.
		@param value The byte written.
	**/
	function applied(at:Int, half:Int, address:Int, value:Int):Void {
		if (half == 0 && address == 0x28) {
			final within = value & 3;
			if (within == 3) return;

			final channel = within + ((value & 4) != 0 ? 3 : 0);
			final on = (value & 0xF0) != 0;

			if (on && keyed[channel]) {
				finish(at, channel);
				tying[channel] = true;
				start(at, channel);
			} else if (on) {
				tying[channel] = false;
				start(at, channel);
			} else if (keyed[channel]) {
				finish(at, channel);
			}

			keyed[channel] = on;
			return;
		}

		if (half == 0 && address == 0x27) {
			song.mode = value & 0xFF;
			return;
		}

		if (half == 0 && address >= 0xA8 && address <= 0xAA) {
			final slot = address - 0xA8 + 1;

			operated(at, slot, ((shadow[0xAC + slot - 1] & 0x3F) << 8) | (value & 0xFF));
			return;
		}

		if (half == 0 && address == 0x22) {
			song.lfoOn = (value & 0x08) != 0;
			song.lfoRate = value & 7;
			return;
		}

		if (half == 0 && address == 0x2B) {
			final on = (value & 0x80) != 0;

			if (!on && dacOn) sampled(at);

			dacOn = on;
			switched(at, on);
			return;
		}

		if (address >= 0x40 && address <= 0x4F && (address & 3) != 3) {
			levelled(at, half, address, value & 0x7F);
			return;
		}

		if (address >= 0x30 && address <= 0x9F && (address & 3) != 3) {
			envelope(at, half, address, value);
			return;
		}

		if (address >= 0xB0 && address <= 0xB2) {
			wired(at, half * 3 + (address & 3), value & 0xFF);
			return;
		}

		if (address >= 0xA0 && address <= 0xA2) {
			final within = address & 3;

			bent(at, half * 3 + within, ((shadow[(half << 8) | (0xA4 + within)] & 0x3F) << 8)
				| (value & 0xFF));
			return;
		}

		if (address >= 0xB4 && address <= 0xB6 && (address & 3) != 3) {
			sided(at, half * 3 + (address & 3), value & 0xFF);
			return;
		}

		if (half == 0 && address == 0x2A) {
			if (!dacOn) return;

			if (dacHead >= 0 && at - dacLast > DAC_GAP) sampled(dacLast + 1);

			if (dacHead < 0) {
				dacHead = at;
				dacBytes.resize(0);
				dacWhen.resize(0);
			}

			dacBytes.push(value & 0xFF);
			dacWhen.push(at);
			dacLast = at;
		}
	}

	static final GROUP_OF:Vector<Int> = Vector.fromArrayCopy([0, 2, 1, 3]);

	final levels:Vector<Int> = new Vector<Int>(24);
	final envelopes:Vector<Int> = new Vector<Int>(24 * 7);

	final stereos:Vector<Int> = new Vector<Int>(6);
	final tunes:Vector<Int> = new Vector<Int>(6);

	/**
		Follows a write to register `$B4`, which carries the stereo bits and both LFO
		sensitivities in one byte.

		@param at The sample the write happens at.
		@param channel Which channel, 0 to 5.
		@param value The byte written.
	**/
	function sided(at:Int, channel:Int, value:Int):Void {
		if (stereos[channel] == value) return;

		final was = stereos[channel];
		stereos[channel] = value;

		final line = lined(channel, mdd.song.Automation.SIDES, 0, was < 0 ? value : was);
		if (line == null || was < 0) return;

		line.add(new mdd.song.Point(ticked(at), value));
	}

	final operators:Vector<Int> = new Vector<Int>(4);

	/**
		Follows a write to one of channel three's separate operator frequencies. A first
		write of zero is the driver clearing the registers rather than the mode being
		used, and is ignored.

		@param at The sample the write happens at.
		@param slot Which of the three, 0 to 2.
		@param word The block and frequency word written.
	**/
	function operated(at:Int, slot:Int, word:Int):Void {
		if (operators[slot] == word) return;
		if (operators[slot] < 0 && word == 0) return;

		operators[slot] = word;

		final line = lined(2, mdd.song.Automation.TUNE, slot, SEEDLESS);
		if (line == null) return;

		line.add(new mdd.song.Point(ticked(at), word));
	}

	/**
		Follows a frequency write while a note is already sounding, which is a vibrato
		or a slide and becomes an automation point rather than being lost.

		@param at The sample the write happens at.
		@param channel Which channel, 0 to 5.
		@param word The block and frequency word written.
	**/
	function bent(at:Int, channel:Int, word:Int):Void {
		final was = tunes[channel];
		tunes[channel] = word;

		if (was < 0 || !keyed[channel]) return;

		final line = lined(channel, mdd.song.Automation.TUNE, 0, SEEDLESS);
		if (line == null) return;

		line.add(new mdd.song.Point(ticked(at),
			mdd.play.Tuning.offset(word, startedOn[channel])));
	}

	static inline final SEEDLESS = 0x40000000;

	/**
		Finds or creates the automation lane a run of writes belongs to.

		@param channel Which channel, 0 to 5.
		@param target Which channel the lane drives.
		@param slot Which lane of it.
		@param first The value to seed a new lane with.
		@return The lane, or null where none can be made.
	**/
	function lined(channel:Int, target:Int, slot:Int, first:Int):Null<mdd.song.Automation> {
		final lane = pattern.lane(channel);

		for (held in lane.automation) {
			if (!held.held(target, slot)) continue;
			return held.points.length >= mdd.song.Automation.ROOM ? null : held;
		}

		final made = new mdd.song.Automation(target, slot);

		lane.automation.push(made);
		if (first != SEEDLESS) made.add(new mdd.song.Point(0, first));

		return made;
	}

	static final SHAPING:Array<Int> = [mdd.song.Automation.TIMBRE,
		mdd.song.Automation.TIMBRE, mdd.song.Automation.ATTACK, mdd.song.Automation.DECAY,
		mdd.song.Automation.SUSTAIN, mdd.song.Automation.RELEASE,
		mdd.song.Automation.LOOP];

	/**
		Follows a write to an operator envelope register while a note sounds.

		@param at The sample the write happens at.
		@param half Which half of the register file.
		@param address The register address.
		@param value The byte written.
	**/
	function envelope(at:Int, half:Int, address:Int, value:Int):Void {
		final base = (address >> 4) - 3;
		if (base < 0 || base > 6 || base == 1) return;

		final target = SHAPING[base];
		final channel = half * 3 + (address & 3);
		final slot = GROUP_OF[(address & 0x0F) >> 2];
		final which = (channel * 4 + slot) * 7 + base;

		if (envelopes[which] == value) return;

		final was = envelopes[which];
		envelopes[which] = value;

		if (was < 0) return;

		final line = lined(channel, target, slot, was);
		if (line == null) return;

		line.add(new mdd.song.Point(ticked(at), value));
	}

	final wirings:Vector<Int> = new Vector<Int>(6);

	/**
		Follows a write to the algorithm and feedback register.

		@param at The sample the write happens at.
		@param channel Which channel, 0 to 5.
		@param value The byte written.
	**/
	function wired(at:Int, channel:Int, value:Int):Void {
		if (wirings[channel] == value) return;

		final was = wirings[channel];
		wirings[channel] = value;

		if (was < 0) return;

		final line = lined(channel, mdd.song.Automation.WIRING, 0, was);
		if (line == null) return;

		line.add(new mdd.song.Point(ticked(at), value));
	}

	/**
		Follows a total level write, which is either the patch being set up or the note
		being made louder or quieter while it sounds.

		@param at The sample the write happens at.
		@param half Which half of the register file.
		@param address The register address.
		@param value The byte written.
	**/
	function levelled(at:Int, half:Int, address:Int, value:Int):Void {
		final channel = half * 3 + (address & 3);
		final slot = GROUP_OF[(address - 0x40) >> 2];
		final which = channel * 4 + slot;

		if (levels[which] == value) return;

		final was = levels[which];
		levels[which] = value;

		if (was < 0 || !everKeyed[channel]) return;

		final fresh = !leveling(channel, slot);
		final line = lined(channel, mdd.song.Automation.LEVEL, slot, 0);
		if (line == null) return;

		if (fresh && was != keyedLevel[which]) {
			line.add(new mdd.song.Point(ticked(startedAt[channel]), was - keyedLevel[which]));
		}

		line.add(new mdd.song.Point(ticked(at), value - keyedLevel[which]));
	}

	/**
		Puts one note into the pattern being built.

		@param part Which part it sounds on.
		@param from The tick it starts on.
		@param until The tick it ends on.
		@param pitch Its MIDI note number.
		@param instrument Which instrument plays it.
		@param velocity How hard it is played.
		@param tied Whether the note after it runs straight on.
	**/
	function placed(part:Part, from:Int, until:Int, pitch:Int, instrument:Int,
			velocity:Int = 127, tied:Bool = false):Void {
		final lane = pattern.lane(part);
		final many = lane.notes.length;

		if (many > 0) {
			final last = lane.notes[many - 1];

			if (last.at + last.length > from) {
				final want = from - last.at;

				if (want < 1) {
					lane.notes.remove(last);
					notes--;
				} else {
					last.length = want;
				}
			}
		}

		final made = new Note(from, until - from, pitch, velocity, instrument);
		made.tied = tied;

		lane.add(made);
		notes++;
	}

	/**
		Begins a note on an FM channel, taking the patch as it stands.

		@param at The sample the write happens at.
		@param channel Which channel, 0 to 5.
	**/
	function start(at:Int, channel:Int):Void {
		everKeyed[channel] = true;
		startedAt[channel] = at;
		startedOn[channel] = pitchOf(channel);
		startedWith[channel] = instrumentFor(channel);
		started[channel] = tying[channel];

		final half = channel >= 3 ? 1 : 0;
		final within = channel % 3;

		for (group in 0...4) {
			keyedLevel[channel * 4 + GROUP[group]] =
				shadow[(half << 8) | (0x40 + group * 4 + within)] & 0x7F;
		}

		restarted(at, channel);
		exact(at, channel);
	}

	/**
		Brings every level lane on a channel back to nought where a note keys on.

		A note starts at whatever level its lane holds, the way a total level holds on the chip from
		one note to the next, but a note read out of a register log already carries the level it was
		keyed at in its velocity. A lane a fade left away from nought would take that level off it a
		second time, so it gets a point of nought on the key on. A driver sets a note's total level
		and keys it on inside one frame, so a write can land on the key on's tick while it is still
		measured from the note before; that point is the one set to nought.

		@param at The sample the key on happens at.
		@param channel Which channel, 0 to 5.
	**/
	function restarted(at:Int, channel:Int):Void {
		final when = ticked(at);

		for (line in pattern.lane(channel).automation) {
			if (line.target != mdd.song.Automation.LEVEL || line.points.length == 0) continue;

			final last = line.points[line.points.length - 1];

			if (last.at == when) last.value = 0;
			else if (line.heldAt(when) != 0) line.add(new mdd.song.Point(when, 0));
		}
	}

	/**
		@param channel Which channel, 0 to 5.
		@param slot Which operator.
		@return Whether the channel already has a level lane for that operator.
	**/
	function leveling(channel:Int, slot:Int):Bool {
		for (held in pattern.lane(channel).automation) {
			if (held.held(mdd.song.Automation.LEVEL, slot)) return true;
		}

		return false;
	}

	/**
		Records the frequency word the driver actually wrote at a key on, wherever it
		differs from the word this would write for the same note.

		@param at The sample the write happens at.
		@param channel Which channel, 0 to 5.
	**/
	function exact(at:Int, channel:Int):Void {
		final word = tunes[channel];
		if (word < 0) return;

		final offset = mdd.play.Tuning.offset(word, startedOn[channel]);
		final when = ticked(at);

		if (offset == 0 && !tuned(channel)) return;

		final line = lined(channel, mdd.song.Automation.TUNE, 0, SEEDLESS);
		if (line == null || line.heldAt(when) == offset) return;

		line.add(new mdd.song.Point(when, offset));
	}

	/**
		@param channel Which channel, 0 to 5.
		@return Whether the channel has been given a frequency yet.
	**/
	function tuned(channel:Int):Bool {
		for (held in pattern.lane(channel).automation) {
			if (held.held(mdd.song.Automation.TUNE, 0)) return true;
		}

		return false;
	}

	/**
		Ends a note on an FM channel and places it.

		@param at The sample the write happens at.
		@param channel Which channel, 0 to 5.
	**/
	function finish(at:Int, channel:Int):Void {
		final from = ticked(startedAt[channel]);
		var until = ticked(at);

		if (at < startedAt[channel]) return;
		if (until <= from) until = from + 1;

		placed(channel, from, until, startedOn[channel], startedWith[channel] < 0
			? instrumentFor(channel) : startedWith[channel], 127, started[channel]);
	}

	/**
		Follows one converter write, gathering a run of them into a sample.

		@param at The sample the write happens at.
	**/
	function sampled(at:Int):Void {
		if (dacHead < 0) return;

		final ends = at > dacLast ? at : dacLast + 1;
		dacHead = -1;

		if (dacBytes.length >= DAC_LEAST && ends > dacWhen[0]) {
			stalled();
			split();
		}

		dacBytes.resize(0);
		dacWhen.resize(0);
	}

	/**
		@return The median gap between converter writes, with real pauses left out, which is what
			the sample rate is taken from.
	**/
	function spacing():Int {
		final many = dacWhen.length;
		if (many < 2) return 6;

		final gaps:Array<Int> = [];
		for (index in 1...many) gaps.push(dacWhen[index] - dacWhen[index - 1]);
		gaps.sort(function(one:Int, two:Int):Int return one - two);

		final middle = gaps[gaps.length >> 1];
		return middle < 1 ? 1 : middle;
	}

	/**
		Finds where the driver stopped writing for long enough to hear, and records it, so
		a piece can be played back the way it sounded on hardware that was busy elsewhere.
	**/
	function stalled():Void {
		final rate = song.tempo.rate < 1 ? 60 : song.tempo.rate;
		final seed = Tempo.TICKS / rate;

		if (seed < 8 || dacWhen.length < 64) return;

		final middle = spacing();

		final at:Array<Int> = [];
		final much:Array<Int> = [];

		var wide = 0;
		var span = 0;

		for (index in 1...dacWhen.length) {
			final apart = dacWhen[index] - dacWhen[index - 1];
			if (apart < 1 || apart > DAC_GAP) continue;

			span += apart;
			if (apart <= middle * 3) continue;

			at.push(dacWhen[index - 1]);
			much.push(apart - middle);
			wide += apart - middle;
		}

		if (at.length < 16 || wide < seed || span < seed * 8) return;

		final room = Math.ceil(seed) + 8;
		final held = new Vector<Int>(room);

		var bestEvery = seed;
		var bestAt = 0;
		var bestMass = 0;

		var every = seed - 3;

		while (every <= seed + 3) {
			final wraps = Math.ceil(every);
			for (index in 0...wraps) held[index] = 0;

			for (index in 0...at.length) {
				var phase = Std.int(at[index] - Math.floor(at[index] / every) * every);
				if (phase < 0) phase = 0;
				if (phase >= wraps) phase = wraps - 1;

				held[phase] += much[index];
			}

			for (start in 0...wraps) {
				var total = 0;
				for (step in 0...STALL_REACH) total += held[(start + step) % wraps];

				if (total <= bestMass) continue;

				bestMass = total;
				bestAt = start;
				bestEvery = every;
			}

			every += 0.05;
		}

		if (bestMass * 2 < wide) return;

		final each = borne(bestEvery);
		if (each < 2) return;

		song.stallAt = bestAt;
		song.stallFor = each;
		song.stallEvery = bestEvery;
	}

	/**
		@param every A candidate stall period, in samples.
		@return How well the gaps in the stream fit it.
	**/
	function borne(every:Float):Int {
		final middle = spacing();
		final most = middle * 8 < DAC_PAUSE ? DAC_PAUSE : middle * 8;
		final each:Array<Float> = [];

		var head = 0;

		while (head < dacWhen.length) {
			var last = head;

			while (last + 1 < dacWhen.length
					&& dacWhen[last + 1] - dacWhen[last] <= most) last++;

			final span = dacWhen[last] - dacWhen[head];
			final many = last - head;

			if (many >= DAC_LEAST && span > every * 2) {
				final rate = paced(head, last);
				final took = many * (Tempo.TICKS / rate);

				if (took > 0 && span > took) each.push((span - took) / (span / every));
			}

			head = last + 1;
		}

		if (each.length < 2) return 0;

		each.sort(function(one:Float, two:Float):Int
			return one < two ? -1 : (one > two ? 1 : 0));

		return Math.round(each[each.length >> 1]);
	}

	/**
		Breaks the one pattern everything was read into one pattern per part, each on its
		own track.
	**/
	function split():Void {
		final middle = spacing();
		final most = middle * 8 < DAC_PAUSE ? DAC_PAUSE : middle * 8;

		var head = 0;

		while (head < dacWhen.length) {
			var last = head;

			while (last + 1 < dacWhen.length
					&& dacWhen[last + 1] - dacWhen[last] <= most) {
				if (last - head >= DAC_LEAST && shifts(last)) break;

				last++;
			}

			hit(head, last, dacWhen[last] + middle, paced(head, last));
			head = last + 1;
		}
	}

	/**
		@param at A write, by index.
		@return Whether it is a frequency write that moves a sounding note.
	**/
	function shifts(at:Int):Bool {
		if (at + STEADY >= dacWhen.length) return false;

		final was = steady(at - STEADY, STEADY);
		final now = steady(at + 1, STEADY);

		if (was < 0.5 || now < 0.5) return false;

		return now > was * STEADY_TURN || now * STEADY_TURN < was;
	}

	final steadied:haxe.ds.Vector<Int> = new haxe.ds.Vector<Int>(STEADY);

	/**
		@param from The first converter write of a run.
		@param many How many writes it holds.
		@return How evenly spaced that run is, which says whether it is one sample or several run
			together.
	**/
	function steady(from:Int, many:Int):Float {
		var held = 0;

		for (index in from + 1...from + many) {
			if (index < 1 || index >= dacWhen.length) continue;

			final apart = dacWhen[index] - dacWhen[index - 1];
			if (apart < 1 || apart > DAC_GAP) continue;

			var at = held;

			while (at > 0 && steadied[at - 1] > apart) {
				steadied[at] = steadied[at - 1];
				at--;
			}

			steadied[at] = apart;
			held++;
		}

		if (held < 4) return -1;

		var total = 0;
		final kept = held * 3 >> 2;

		for (index in 0...kept) total += steadied[index];

		return kept < 1 ? -1 : total / kept;
	}

	/**
		@param head The first converter write of a run.
		@param last The last.
		@return The rate the run was written at, in hertz, from the gaps between writes with pauses
			left out.
	**/
	function paced(head:Int, last:Int):Int {
		if (song.stallAt < 0) {
			final span = dacWhen[last] - dacWhen[head];
			final many = last - head;

			if (span > 0 && many > 0) {
				final rate = Math.round(many * (Tempo.TICKS / span));
				return rate < 2000 ? 2000 : (rate > Tempo.TICKS ? Tempo.TICKS : rate);
			}
		}

		final gaps:Array<Int> = [];

		for (index in head + 1...last + 1) {
			final apart = dacWhen[index] - dacWhen[index - 1];
			if (apart >= 0 && apart <= DAC_GAP) gaps.push(apart);
		}

		if (gaps.length < 4) return Std.int(Tempo.TICKS / spacing());

		gaps.sort(function(one:Int, two:Int):Int return one - two);

		final middle = gaps[gaps.length >> 1];
		final most = (middle < 1 ? 1 : middle) * 4;

		var total = 0;
		var counted = 0;

		for (apart in gaps) {
			if (apart > most) break;

			total += apart;
			counted++;
		}

		if (counted < 1 || total < 1) return Std.int(Tempo.TICKS / spacing());

		final rate = Math.round(counted * (Tempo.TICKS / total));
		return rate < 2000 ? 2000 : (rate > Tempo.TICKS ? Tempo.TICKS : rate);
	}

	/**
		Turns one run of converter writes into a sample and a note that plays it.

		@param head The first write of the run.
		@param last The last.
		@param ends The sample the run finishes at.
		@param rate The rate it was written at.
	**/
	function hit(head:Int, last:Int, ends:Int, rate:Int):Void {
		if (last - head + 1 < DAC_LEAST) return;

		final from = ticked(dacWhen[head]);
		var until = ticked(ends);
		if (until <= from) until = from + 1;

		evened(head, last);
		if (dacTake.length < DAC_LEAST) return;

		final which = sampleInstrument(rate);
		if (which < 0) return;

		placed(Part.Dac, from, until, rootOf(which), which);
	}

	/**
		Fills in the gaps of a run so the sample is evenly spaced, which is what playing
		it back at one rate needs.

		@param head The first write of the run.
		@param last The last.
	**/
	function evened(head:Int, last:Int):Void {
		dacTake.resize(0);
		for (index in head...last + 1) dacTake.push(dacBytes[index]);
	}

	/**
		Follows one square part write, which may be half of a two byte period.

		@param at The sample the write happens at.
		@param value The byte written.
	**/
	function square(at:Int, value:Int):Void {
		if ((value & 0x80) != 0) {
			latched = (value >> 4) & 0x07;
			final channel = latched >> 1;

			if ((latched & 1) != 0) attenuated(at, channel, value & 0x0F);
			else if (channel < 3) {
				psgPeriod[channel] = (psgPeriod[channel] & 0x3F0) | (value & 0x0F);
				slid(at, channel);
			} else hissed(at, value & 0x0F);

			return;
		}

		final channel = latched >> 1;

		if ((latched & 1) != 0) {
			attenuated(at, channel, value & 0x0F);
			return;
		}

		if (channel >= 3) return;

		psgPeriod[channel] = (psgPeriod[channel] & 0x0F) | ((value & 0x3F) << 4);
		slid(at, channel);
	}

	/**
		Follows the sample channel being turned on or off.

		@param at The sample the write happens at.
		@param on Whether it took channel six.
	**/
	function switched(at:Int, on:Bool):Void {
		final line = lined(10, mdd.song.Automation.TUNE, 0, SEEDLESS);
		if (line == null) return;

		line.add(new mdd.song.Point(ticked(at), on ? 1 : 0));
	}

	/**
		Follows a write to the noise control register.

		@param at The sample the write happens at.
		@param value The nibble written.
	**/
	function hissed(at:Int, value:Int):Void {
		final was = noiseMode;
		noiseMode = value;

		final line = lined(9, mdd.song.Automation.TUNE, 0, SEEDLESS);
		if (line == null) return;

		line.add(new mdd.song.Point(ticked(at), value));
	}

	/**
		Follows a square period change while a note sounds, which becomes an automation
		point rather than a new note.

		@param at The sample the write happens at.
		@param channel Which square channel, 0 to 3.
	**/
	function slid(at:Int, channel:Int):Void {
		final line = lined(6 + channel, mdd.song.Automation.TUNE, 0, SEEDLESS);
		if (line == null) return;

		final offset = everSquared[channel]
			? psgPeriod[channel] - mdd.play.Stream.periodOf(psgNote[channel])
			: psgPeriod[channel];

		line.add(new mdd.song.Point(ticked(at), offset));
	}

	/**
		Follows a square attenuation write, which is how a driver runs an envelope by
		hand, and gathers the run of them into one.

		@param at The sample the write happens at.
		@param channel Which square channel, 0 to 3.
		@param level The attenuation written.
	**/
	function attenuated(at:Int, channel:Int, level:Int):Void {
		final was = psgLevel[channel];
		psgLevel[channel] = level;

		if (level < 15 && was >= 15) {
			psgFrom[channel] = at;
			psgNote[channel] = channel < 3 ? squareNote(psgPeriod[channel]) : 60;
			everSquared[channel] = true;

			psgWhen[channel].resize(0);
			psgHeld[channel].resize(0);
			psgWhen[channel].push(at);
			psgHeld[channel].push(level);

			final line = lined(6 + channel, mdd.song.Automation.LEVEL, 0, SEEDLESS);
			if (line != null) line.add(new mdd.song.Point(ticked(at), 0));

			if (channel < 3) slid(at, channel);
			return;
		}

		if (level < 15 && psgFrom[channel] >= 0) {
			if (level == was) return;

			psgWhen[channel].push(at);
			psgHeld[channel].push(level);

			final line = lined(6 + channel, mdd.song.Automation.LEVEL, 0, SEEDLESS);
			if (line != null) {
				line.add(new mdd.song.Point(ticked(at), level - psgHeld[channel][0]));
			}

			return;
		}

		if (level >= 15 && was < 15 && psgFrom[channel] >= 0) {
			final head = psgFrom[channel];
			final from = ticked(head);
			var until = ticked(at);
			psgFrom[channel] = -1;

			if (at <= head) return;
			if (until <= from) until = from + 1;

			final loudest = psgHeld[channel][0];
			final velocity = mdd.play.Velocity.loudness(loudest);

			placed(6 + channel, from, until, psgNote[channel],
				squareInstrument(channel, head, at), velocity < 1 ? 1 : velocity);
		}
	}

	function shaped(channel:Int, head:Int, tail:Int):Array<Int> {
		final when = psgWhen[channel];
		final held = psgHeld[channel];
		final steps:Array<Int> = [];

		if (when.length == 0) return steps;

		final loudest = held[0];
		var many = Math.ceil((tail - head) / ENVELOPE_TICKS);

		if (many < 1) many = 1;
		if (many > ENVELOPE_STEPS) many = ENVELOPE_STEPS;

		var at = 0;

		for (step in 0...many) {
			final want = head + step * ENVELOPE_TICKS;
			while (at + 1 < when.length && when[at + 1] <= want) at++;

			final away = held[at] - loudest;
			steps.push(away < 0 ? 0 : (away > 15 ? 15 : away));
		}

		while (steps.length > 1 && steps[steps.length - 1] == steps[steps.length - 2]) {
			steps.pop();
		}

		return steps;
	}

	static function moves(lane:mdd.song.Lane):Bool {
		for (line in lane.automation) {
			if (line.points.length < 2) continue;

			final first = line.points[0].value;
			for (point in line.points) if (point.value != first) return true;
		}

		return false;
	}

	function parted():Void {
		song.split(pattern);
	}

	function close(at:Int):Void {
		for (channel in 0...6) if (keyed[channel]) finish(at, channel);
		for (channel in 0...4) if (psgFrom[channel] >= 0) attenuated(at, channel, 15);
		if (dacOn) sampled(at);
	}

	function pitchOf(channel:Int):Int {
		final half = channel >= 3 ? 1 : 0;
		final within = channel % 3;

		final high = shadow[(half << 8) | (0xA4 + within)];
		final low = shadow[(half << 8) | (0xA0 + within)];

		final block = (high >> 3) & 7;
		final number = ((high & 7) << 8) | low;

		if (number == 0) return 60;

		final hertz = number * (Ym2612.CLOCK / Ym2612.PER_SAMPLE) / 1048576.0
			* Math.pow(2, block - 1);

		return nearest(hertz);
	}

	function squareNote(period:Int):Int {
		if (period < 1) return 60;
		return nearest(Sn76489.CLOCK / (32.0 * period));
	}

	function nearest(hertz:Float):Int {
		if (hertz <= 0) return 60;

		final exact = 69 + 12 * Math.log(hertz / 440.0) / Math.log(2);
		var note = Math.round(exact);

		if (note < 0) note = 0;
		if (note > 127) note = 127;

		final off = Math.abs(exact - note) * 100;
		if (off > worstCents) worstCents = off;

		sounded++;
		if (off > 25) offGrid++;
		else if (off < 1) onGrid++;

		return note;
	}

	function instrumentFor(channel:Int):Int {
		final half = channel >= 3 ? 1 : 0;
		final within = channel % 3;

		final patch = new Patch();
		final wiring = shadow[(half << 8) | (0xB0 + within)];

		patch.algorithm = wiring & 7;
		patch.feedback = (wiring >> 3) & 7;

		final sides = shadow[(half << 8) | (0xB4 + within)];
		patch.ams = (sides >> 4) & 3;
		patch.pms = sides & 7;

		for (group in 0...4) {
			final slot = GROUP[group];
			final at = group * 4 + within;

			final tune = shadow[(half << 8) | (0x30 + at)];
			patch.detune[slot] = (tune >> 4) & 7;
			patch.multiple[slot] = tune & 0x0F;

			patch.totalLevel[slot] = shadow[(half << 8) | (0x40 + at)] & 0x7F;

			final attack = shadow[(half << 8) | (0x50 + at)];
			patch.keyScale[slot] = (attack >> 6) & 3;
			patch.attack[slot] = attack & 0x1F;

			final decay = shadow[(half << 8) | (0x60 + at)];
			patch.tremolo[slot] = (decay & 0x80) != 0;
			patch.decay[slot] = decay & 0x1F;

			patch.sustain[slot] = shadow[(half << 8) | (0x70 + at)] & 0x1F;

			final level = shadow[(half << 8) | (0x80 + at)];
			patch.sustainLevel[slot] = (level >> 4) & 0x0F;
			patch.release[slot] = level & 0x0F;

			patch.ssg[slot] = shadow[(half << 8) | (0x90 + at)] & 0x0F;
		}

		return held(patch, Part.Fm1);
	}

	function held(patch:Patch, kind:Part):Int {
		for (index in 0...song.instruments.length) {
			final instrument = song.instruments[index];
			if (instrument.patch == null) continue;
			if (same(instrument.patch, patch)) return index;
		}

		final instrument = new Instrument("patch " + song.instruments.length, kind);
		instrument.patch = patch;
		song.instrument(instrument);

		return song.instruments.length - 1;
	}

	static function same(one:Patch, two:Patch):Bool {
		if (one.algorithm != two.algorithm || one.feedback != two.feedback) return false;
		if (one.ams != two.ams || one.pms != two.pms) return false;

		for (slot in 0...Patch.SLOTS) {
			if (one.detune[slot] != two.detune[slot]) return false;
			if (one.multiple[slot] != two.multiple[slot]) return false;
			if (one.totalLevel[slot] != two.totalLevel[slot]) return false;
			if (one.keyScale[slot] != two.keyScale[slot]) return false;
			if (one.attack[slot] != two.attack[slot]) return false;
			if (one.decay[slot] != two.decay[slot]) return false;
			if (one.sustain[slot] != two.sustain[slot]) return false;
			if (one.sustainLevel[slot] != two.sustainLevel[slot]) return false;
			if (one.release[slot] != two.release[slot]) return false;
			if (one.ssg[slot] != two.ssg[slot]) return false;
			if (one.tremolo[slot] != two.tremolo[slot]) return false;
		}

		return true;
	}

	var squares:Int = -1;

	function squareInstrument(channel:Int, head:Int, tail:Int):Int {
		final steps = shaped(channel, head, tail);
		final noise = channel == 3 ? noiseMode : -1;

		for (index in 0...shapes.length) {
			final held = song.instruments[shapes[index]];
			if (held.envelope == null) continue;
			if (noise >= 0 && held.envelope.noise != noise) continue;
			if (noise < 0 && held.kind.noise()) continue;
			if (noise >= 0 && !held.kind.noise()) continue;
			if (!alikeShape(held.envelope.steps, steps)) continue;

			return shapes[index];
		}

		final kind = channel == 3 ? Part.Noise : Part.Psg1;
		final instrument = new Instrument((channel == 3 ? "noise " : "square ")
			+ (shapes.length + 1), kind);

		if (instrument.envelope != null) {
			for (step in steps) instrument.envelope.steps.push(step);
			if (noise >= 0) instrument.envelope.noise = noise;
		}

		song.instrument(instrument);
		shapes.push(song.instruments.length - 1);

		if (squares < 0) squares = song.instruments.length - 1;
		return song.instruments.length - 1;
	}

	static function alikeShape(one:Array<Int>, two:Array<Int>):Bool {
		if (one.length != two.length) return false;
		for (index in 0...one.length) if (one[index] != two[index]) return false;

		return true;
	}

	/**
		Where a hit is drawn.

		@param which An instrument the converter plays.
		@return The key its recording sits on, so the same hit always lands on the
			same row and two different ones do not share it.
	**/
	function rootOf(which:Int):Int {
		final instrument = song.instrumentAt(which);
		if (instrument == null) return DAC_ROOT;

		final sample = song.sampleAt(instrument.sample);
		return sample == null ? DAC_ROOT : sample.root;
	}

	function sampleInstrument(rate:Int):Int {
		final many = dacTake.length;
		final head = loudTaken(many);

		final now = new Vector<Float>(PRINT);
		printed(dacTake, head, many - head, now);

		for (index in 0...prints.length) {
			if (index >= song.samples.length) break;
			if (!alike(song.samples[index], head, now, prints[index])) continue;

			return kits[index];
		}

		if (dacHeld + many > DAC_ROOM) return kits.length == 0 ? -1 : kits[0];

		final held = new Vector<Int>(many);
		for (index in 0...many) held[index] = dacTake[index];

		final sample = new Sample("hit " + (song.samples.length + 1), rate,
			(DAC_ROOT + kits.length) % KEYS);
		sample.hold(held);
		song.sample(sample);

		final instrument = new Instrument(sample.name, Part.Dac);
		instrument.sample = song.samples.length - 1;
		song.instrument(instrument);

		kits.push(song.instruments.length - 1);
		prints.push(now);
		dacHeld += many;

		return song.instruments.length - 1;
	}

	static function loudIn(bytes:Vector<Int>, many:Int):Int {
		var at = 0;

		while (at < many) {
			final byte = bytes[at] - 128;
			if ((byte < 0 ? -byte : byte) > DAC_QUIET) break;

			at++;
		}

		return at;
	}

	/**
		How many points a recording is reduced to before two are compared.
	**/
	public static inline final PRINT = PRINT_LOUD + PRINT_BANDS;

	/**
		How many of those points say how loud the sound is over its length. The rest
		say how its energy is spread over frequency.
	**/
	static inline final PRINT_LOUD = 24;

	/**
		How many bands the energy is split into, and the lowest of them as a share of
		the rate, each band twice the one below it.
	**/
	static inline final PRINT_BANDS = 24;
	static inline final PRINT_LOWEST = 0.0025;
	static inline final PRINT_OCTAVE = 0.32;

	/**
		How many bytes of a recording the bands are read over, so a long passage does
		not cost more to print than a drum does.
	**/
	static inline final PRINT_REACH = 4096;

	/**
		How far apart two prints may be and still be one sound, averaged over every
		point, where each point runs nought to one.
	**/
	static inline final PRINT_APART = 0.07;

	/**
		Reduces a recording to a short run of numbers that says what it sounds like
		rather than what bytes it holds.

		Half of the numbers are how loud it is over its length and half are how its
		energy is spread over frequency, and both are taken at the same count however
		long the recording is.

		Three things make two writes of one drum come back as different bytes, and the
		print is built to see past all three. A driver writes at whatever rate it is
		running at, so one capture is stretched against the other: reading both at the
		same number of points takes that out. A drum is hit harder in one bar than the
		next: dividing by the loudest point takes that out. A run is cut a few bytes
		earlier or later than the last one: a band of energy does not move when the
		waveform slides, so the frequency half does not care where the cut fell.

		@param bytes The run the converter has taken and not yet kept.
		@param head Where the sound starts, past any silence.
		@param many How many bytes of it there are.
		@param into Where to write the print, which must hold `PRINT` numbers.
	**/
	public static function printed(bytes:Array<Int>, head:Int, many:Int,
			into:Vector<Float>):Void {
		many = sounding(bytes, head, many);

		var most = 0.0;

		for (point in 0...PRINT_LOUD) {
			final from = head + Std.int(many * point / PRINT_LOUD);
			final until = head + Std.int(many * (point + 1) / PRINT_LOUD);

			var total = 0.0;
			var counted = 0;

			for (at in from...(until > from ? until : from + 1)) {
				if (at < 0 || at >= bytes.length) continue;

				final value = bytes[at] - 128;
				total += value * value;
				counted++;
			}

			final power = counted == 0 ? 0.0 : Math.sqrt(total / counted);

			into[point] = power;
			if (power > most) most = power;
		}

		if (most <= 0) most = 1;
		for (point in 0...PRINT_LOUD) into[point] = into[point] / most;

		banded(bytes, head, many, into);
	}

	/**
		How much of a run is the sound, with the silence at the end left off.

		A driver stops writing when it stops, so one write of a drum carries a longer
		tail of nothing than the next. Reading a print over the whole of both
		stretches one against the other and puts two writes of one drum further
		apart than two different drums, so the quiet at the end comes off first.

		@param bytes The run.
		@param head Where the sound starts.
		@param many How many bytes follow it.
		@return How many of them carry any sound.
	**/
	static function sounding(bytes:Array<Int>, head:Int, many:Int):Int {
		var at = many;

		while (at > 0) {
			final where = head + at - 1;
			if (where < 0 || where >= bytes.length) { at--; continue; }

			final value = bytes[where] - 128;
			if ((value < 0 ? -value : value) > DAC_QUIET) break;

			at--;
		}

		return at < DAC_LEAST ? (many < DAC_LEAST ? many : DAC_LEAST) : at;
	}

	/**
		Fills in the half of a print that says how the energy is spread over frequency.

		The bands are spaced by doubling rather than evenly, because hearing is, and
		because a drum's body and its snap sit decades apart rather than a fixed number
		of hertz apart. Each band is read where the recording is, so the rate the
		driver happened to be running at moves a band by a fraction of its width rather
		than off the end.

		@param bytes The run.
		@param head Where the sound starts.
		@param many How many bytes of it there are.
		@param into The print, whose second half this writes.
	**/
	static function banded(bytes:Array<Int>, head:Int, many:Int, into:Vector<Float>):Void {
		final reach = many < PRINT_REACH ? many : PRINT_REACH;
		var most = 0.0;

		for (band in 0...PRINT_BANDS) {
			final turn = PRINT_LOWEST * Math.pow(2, band * PRINT_OCTAVE);
			final step = 2 * Math.PI * turn;

			final cosStep = Math.cos(step);
			final sinStep = Math.sin(step);

			var cosNow = 1.0;
			var sinNow = 0.0;
			var real = 0.0;
			var imaginary = 0.0;

			for (at in 0...reach) {
				final where = head + at;
				final value = where >= 0 && where < bytes.length ? bytes[where] - 128 : 0;

				real += value * cosNow;
				imaginary += value * sinNow;

				final held = cosNow * cosStep - sinNow * sinStep;
				sinNow = cosNow * sinStep + sinNow * cosStep;
				cosNow = held;
			}

			final power = Math.sqrt(real * real + imaginary * imaginary) / reach;

			into[PRINT_LOUD + band] = power;
			if (power > most) most = power;
		}

		if (most <= 0) most = 1;

		for (band in 0...PRINT_BANDS) {
			final share = into[PRINT_LOUD + band] / most;
			into[PRINT_LOUD + band] = Math.log(share * 99 + 1) / Math.log(100);
		}
	}

	/**
		@param one A print.
		@param two Another.
		@return How far apart they are, averaged over every point.
	**/
	public static function apartPrints(one:Vector<Float>, two:Vector<Float>):Float {
		var total = 0.0;

		for (point in 0...PRINT) {
			final away = one[point] - two[point];
			total += away < 0 ? -away : away;
		}

		return total / PRINT;
	}

	function loudTaken(many:Int):Int {
		var at = 0;

		while (at < many) {
			final byte = dacTake[at] - 128;
			if ((byte < 0 ? -byte : byte) > DAC_QUIET) break;

			at++;
		}

		return at;
	}

	/**
		Whether a recording already taken and the run in hand are one sound.

		The bytes themselves are not compared. A driver writes a drum at whatever
		rate it is running at, so two writes of one sound come back at different
		lengths with the bytes stretched against each other, and sliding one along
		the other never lines them up: reading both at the same number of points
		is what takes the stretch out.

		A length is still asked for, loosely, so that a blip and a passage of music
		are never called one sound however alike their shapes are.

		The bytes are still read where the print does not settle it. The two tests
		catch different things: a print sees one drum written at two rates, and the
		bytes see two writes that line up exactly but whose prints fall either side
		of the line. Either is enough.

		@param sample A recording already taken.
		@param rest Where the run in hand starts, past any silence.
		@param now The print of the run in hand.
		@param held The print of the recording, worked out when it was taken.
		@return Whether they are the same sound.
	**/
	function alike(sample:Sample, rest:Int, now:Vector<Float>,
			held:Vector<Float>):Bool {
		final one = sample.length();
		final two = dacTake.length;

		if (one < DAC_LEAST || two < DAC_LEAST) return false;

		final head = loudIn(sample.bytes, one);

		final left = one - head;
		final right = two - rest;

		if (left < DAC_LEAST || right < DAC_LEAST) return false;

		final shorter = left < right ? left : right;
		final longer = left > right ? left : right;

		if (shorter * DAC_STRETCH < longer) return false;

		if (apartPrints(held, now) <= PRINT_APART) return true;

		if (shorter * 5 < longer * 4) return false;

		var best = 256.0;

		for (slip in -DAC_SLIP...DAC_SLIP + 1) {
			final away = apartBy(sample.bytes, head, rest, shorter, slip);

			if (away < best) best = away;
			if (best <= DAC_APART) return true;
		}

		return false;
	}

	function apartBy(bytes:Vector<Int>, head:Int, rest:Int, many:Int, slip:Int):Float {
		var total = 0.0;
		var counted = 0;

		for (index in 0...many) {
			final left = head + index;
			final right = rest + index + slip;

			if (left < 0 || left >= bytes.length) continue;
			if (right < 0 || right >= dacTake.length) continue;

			final away = bytes[left] - dacTake[right];

			total += away < 0 ? -away : away;
			counted++;
		}

		return counted < DAC_LEAST ? 256 : total / counted;
	}
	function session():Void {
		if (song.instruments.length == 0) return;

		final bank = song.banked("from the import", false);
		for (index in 0...song.instruments.length) bank.add(index);

		song.banks[0].instruments.resize(0);
	}

	function settle():Void {
		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final lane = pattern.lane(part);

			if (lane.notes.length > 0) {
				song.rack[index] = lane.notes[0].instrument;
				continue;
			}

			if (part.sampled()) song.rack[index] = -1;
			else if (part.noise()) song.rack[index] = mdd.song.Shipped.firstNoise(song);
			else if (part.square()) song.rack[index] = mdd.song.Shipped.firstSquare(song);
			else song.rack[index] = mdd.song.Shipped.firstFm(song);
		}
	}
}
