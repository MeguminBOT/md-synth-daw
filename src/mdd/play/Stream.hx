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
package mdd.play;

import haxe.ds.Vector;
import mdd.chip.Sn76489;
import mdd.chip.Ym2612;
import mdd.song.Envelope;
import mdd.song.Part;
import mdd.song.Patch;
import mdd.song.Tempo;

/**
	The one thing in this application that produces a register write.

	Playback, the export, the register timeline and the hardware monitor all consume
	the same stream from here, so what is heard, what is drawn and what is written to a
	file cannot drift apart. A panel that wants to audition a note asks this rather
	than touching a chip, and the checks compare the live stream against the offline
	one on every run.

	It is a buffer of timed writes, not a chip: nothing here decides when a note
	happens. The sequencer does that and calls in.
**/
@:unreflective
final class Stream {
	/**
		Marks a write as belonging to the FM part.
	**/
	public static inline final YM = 0;

	/**
		Marks a write as belonging to the square part.
	**/
	public static inline final PSG = 1;

	/**
		Middle C as a MIDI note number, which is where tuning is measured from.
	**/
	public static inline final MIDDLE = 60;

	/**
		Operator slot to register offset. The part lays operators out 1, 3, 2, 4.
	**/
	static final GROUP:Vector<Int> = Vector.fromArrayCopy([0, 2, 1, 3]);

	/**
		The twelve semitone frequency words one octave holds, built from the part's clock
		rather than copied from a driver, because every driver rounds its own way.
	**/
	public static final FM_NOTES:Vector<Int> = fmNotes();

	/**
		A period for each of the 128 MIDI notes, clamped to the ten bits the part has.
	**/
	public static final PSG_PERIODS:Vector<Int> = psgPeriods();

	/**
		Builds `FM_NOTES` from the part's clock and equal temperament.

		@return Twelve frequency words, one per semitone.
	**/
	static function fmNotes():Vector<Int> {
		final out = new Vector<Int>(12);
		final rate = Ym2612.CLOCK / Ym2612.PER_SAMPLE;

		for (i in 0...12) {
			final hz = 261.6255653005986 * Math.pow(2, i / 12.0);
			out[i] = Math.round(hz * 1048576.0 / rate / 8.0);
		}

		return out;
	}

	/**
		Builds `PSG_PERIODS` the same way.

		@return One period per MIDI note, clamped to what the part can reach.
	**/
	static function psgPeriods():Vector<Int> {
		final out = new Vector<Int>(128);

		for (note in 0...128) {
			final hz = 440.0 * Math.pow(2, (note - 69) / 12.0);
			final period = Math.round(Sn76489.CLOCK / (32.0 * hz));

			out[note] = period < 1 ? 1 : (period > 1023 ? 1023 : period);
		}

		return out;
	}

	/**
		@param note A MIDI note number.
		@return The block and frequency word packed into one value, block in bits 11 to 13.
	**/
	public static inline function wordOf(note:Int):Int {
		return ((blockOf(note) & 7) << 11) | (frequencyOf(note) & 0x7FF);
	}

	/**
		@param note A MIDI note number.
		@return The block it falls in, clamped to the eight the part has.
	**/
	public static inline function blockOf(note:Int):Int {
		final octave = Std.int(note / 12) - 1;
		return octave < 0 ? 0 : (octave > 7 ? 7 : octave);
	}

	/**
		@param note A MIDI note number.
		@return Its frequency word, which is the same in every octave.
	**/
	public static inline function frequencyOf(note:Int):Int {
		return FM_NOTES[note % 12];
	}

	/**
		@param note A MIDI note number. Anything outside 0 to 127 is clamped.
		@return The square period for it.
	**/
	public static inline function periodOf(note:Int):Int {
		return PSG_PERIODS[note < 0 ? 0 : (note > 127 ? 127 : note)];
	}

	/**
		How many writes this stream can hold before it starts dropping them.
	**/
	public var capacity(default, null):Int;

	/**
		How many writes are in it now.
	**/
	public var count(default, null):Int = 0;

	/**
		How many writes were thrown away for want of room. Anything but nought here is a
		buffer too small for the span being rendered, and it is worth reporting.
	**/
	public var dropped(default, null):Int = 0;

	/**
		The most writes a stream that grows will reach before it starts dropping them, which
		is the last stop rather than a size anything is expected to need.
	**/
	public static inline final CEILING = 1 << 25;

	/**
		Whether a full buffer is made larger rather than dropping the write.

		**It is off, and it stays off for anything the render thread reads.** Growing
		replaces the four vectors, and a reader holding the old ones while the writer swaps
		them is a race nothing would report. An offline bounce has one thread writing and
		nothing reading until it has finished, which is why that is the one place this is
		turned on: the alternative there is reserving the worst case in one block, half a
		gigabyte for a quarter of an hour, on a machine that may not have it.
	**/
	public var grows:Bool = false;

	var ticks:Vector<Int>;
	var kinds:Vector<Int>;
	var ports:Vector<Int>;
	var values:Vector<Int>;
	var noised:Int = -1;
	final settled:Vector<Int> = new Vector<Int>(512);

	/**
		Per FM channel, whether the last key write keyed it on: 1 on, 0 off, -1 not known since the
		last `forget`.
	**/
	final keyed:Vector<Int> = new Vector<Int>(6);
	final words:Vector<Int> = new Vector<Int>(10);
	final whens:Vector<Int> = new Vector<Int>(10);

	/**
		How many register writes a second to reserve at the start. It is a guess at a busy
		piece rather than the worst case, because a stream that grows costs a copy where it
		is wrong and half a gigabyte where the worst case is reserved and never used.
	**/
	public static inline final PER_SECOND = 2048;

	/**
		The least to reserve, whatever the span.
	**/
	public static inline final LEAST_ROOM = 1 << 18;

	/**
		The most to reserve at the start. Past this the stream grows into what it needs.
	**/
	public static inline final MOST_ROOM = 1 << 22;

	/**
		@param span How many output samples the span covers.
		@return How many writes to reserve for it.
	**/
	public static function roomFor(span:Int):Int {
		final seconds = span / Tempo.TICKS;
		final want = Std.int(seconds * PER_SECOND);

		return want < LEAST_ROOM ? LEAST_ROOM : (want > MOST_ROOM ? MOST_ROOM : want);
	}

	/**
		Builds a stream for a span that is written once and read afterwards, which is what
		every export and every offline render is.

		@param span How many output samples the span covers.
		@return A stream reserved for a piece that busy, and free to grow past it.
	**/
	public static function reserved(span:Int):Stream {
		final made = new Stream(roomFor(span));
		made.grows = true;

		return made;
	}

	public function new(capacity:Int = 8192) {
		this.capacity = capacity < 16 ? 16 : capacity;

		ticks = new Vector<Int>(this.capacity);
		kinds = new Vector<Int>(this.capacity);
		ports = new Vector<Int>(this.capacity);
		values = new Vector<Int>(this.capacity);

		forget();
	}

	/**
		Doubles the room, where this stream is one that grows.

		Doubling rather than adding a block keeps the copying to a constant share of the
		writing however large it gets, and the buffer that is thrown away is half the size
		of the one taking over, so the peak is one and a half times what is kept rather
		than twice it.

		@return Whether there is now room for another write.
	**/
	function widens():Bool {
		if (!grows || capacity >= CEILING) return false;

		final want = capacity > CEILING >> 1 ? CEILING : capacity * 2;

		ticks = wider(ticks, want, count);
		kinds = wider(kinds, want, count);
		ports = wider(ports, want, count);
		values = wider(values, want, count);

		capacity = want;
		return true;
	}

	/**
		@param from The buffer that is full.
		@param room How many it should hold.
		@param many How many of it are worth carrying over.
		@return A buffer of that size holding what the old one held.
	**/
	static function wider(from:Vector<Int>, room:Int, many:Int):Vector<Int> {
		final out = new Vector<Int>(room);
		Vector.blit(from, 0, out, 0, many);

		return out;
	}

	/**
		Forgets what the chips are already holding, so the next write of every register is
		made again rather than skipped as redundant. A seek has to do this.
	**/
	public function forget():Void {
		noised = -1;
		for (index in 0...settled.length) settled[index] = -1;
		for (index in 0...keyed.length) keyed[index] = -1;
		for (index in 0...words.length) words[index] = -1;
		for (index in 0...whens.length) whens[index] = -1;
	}

	/**
		Empties the buffer without forgetting what the chips hold.
	**/
	public function clear():Void {
		count = 0;
		dropped = 0;
	}

	/**
		@param index A position below `count`.
		@return When that write happens, in output samples from the start of the span.
	**/
	public inline function tickAt(index:Int):Int {
		return ticks[index];
	}

	/**
		@param index A position below `count`.
		@return Which part it is for, `YM` or `PSG`.
	**/
	public inline function kindAt(index:Int):Int {
		return kinds[index];
	}

	/**
		@param index A position below `count`.
		@return The bus port it goes to.
	**/
	public inline function portAt(index:Int):Int {
		return ports[index];
	}

	/**
		@param index A position below `count`.
		@return The byte it carries.
	**/
	public inline function valueAt(index:Int):Int {
		return values[index];
	}

	/**
		Appends one write exactly as given, with no deduplication. Everything else here
		ends up calling this. A full buffer counts the write in `dropped` and keeps going.

		@param tick When the write happens, in output samples from the start of the span.
		@param kind Which part, `YM` or `PSG`.
		@param port The bus port.
		@param value The byte to write.
	**/
	public function raw(tick:Int, kind:Int, port:Int, value:Int):Void {
		if (count >= capacity && !widens()) {
			dropped++;
			return;
		}

		ticks[count] = tick;
		kinds[count] = kind;
		ports[count] = port & 3;
		values[count] = value & 0xFF;
		count++;
	}

	/**
		One FM register write, as the address byte and then the value. A register whose
		value has not changed is skipped, unless it is one that must always be written.

		@param tick When the write happens, in output samples from the start of the span.
		@param half Which half of the register file, 0 or 1.
		@param at The register address within that half.
		@param value The byte to write.
	**/
	public inline function ym(tick:Int, half:Int, at:Int, value:Int):Void {
		final byte = value & 0xFF;
		final index = (half << 8) | at;

		if (settled[index] != byte || !settles(at)) {
			settled[index] = byte;

			raw(tick, YM, half * 2, at);
			raw(tick, YM, half * 2 + 1, byte);
		}
	}

	/**
		@param at A register address.
		@return True where the register may be skipped when its value has not changed. The key on
			register and the frequency latches may not.
	**/
	static inline function settles(at:Int):Bool {
		return (at >= 0x30 && at < 0xA0) || at == 0x2A || (at >= 0xB0 && at <= 0xB6) || at == 0x22;
	}

	/**
		One square part write, which is a single byte.

		@param tick When the write happens, in output samples from the start of the span.
		@param value The byte to write.
	**/
	public inline function psg(tick:Int, value:Int):Void {
		raw(tick, PSG, 0, value);
	}

	/**
		@param half Which half of the register file, 0 or 1.
		@param address The register address within that half.
		@return Which channel that register belongs to, or -1 where it belongs to none.
	**/
	public static function ymPart(half:Int, address:Int):Int {
		if (address == 0x2A || address == 0x2B) return Part.Dac.index();
		if (address < 0x30 || address > 0xB6) return -1;

		if (half == 0 && address >= 0xA8 && address <= 0xAE) return 2;

		final channel = address & 3;
		if (channel == 3) return -1;

		return half * 3 + channel;
	}

	/**
		@param value A byte written to register `$28`.
		@return Which channel it names, or -1 where it names none.
	**/
	public static function keyPart(value:Int):Int {
		final channel = value & 3;
		if (channel == 3) return -1;

		return ((value & 4) != 0 ? 3 : 0) + channel;
	}

	static inline function halfOf(part:Part):Int {
		return part.index() >= 3 ? 1 : 0;
	}

	static inline function channelOf(part:Part):Int {
		return part.index() % 3;
	}

	/**
		Writes a whole patch to a channel: every operator field, the algorithm, the
		feedback and the sensitivities.

		@param tick When the write happens, in output samples from the start of the span.
		@param part Which channel the write is for.
		@param patch The patch to write.
		@param velocity What to scale the carriers by, 0 to 127.
	**/
	public function patch(tick:Int, part:Part, patch:Patch, velocity:Int):Void {
		if (!part.fm()) return;

		final half = halfOf(part);
		final channel = channelOf(part);

		for (group in 0...4) {
			final slot = GROUP[group];
			final at = group * 4 + channel;

			ym(tick, half, 0x30 + at, ((patch.detune[slot] & 7) << 4) | (patch.multiple[slot] & 0x0F));
			ym(tick, half, 0x40 + at, levelOf(patch, slot, velocity));
			ym(tick, half, 0x50 + at, ((patch.keyScale[slot] & 3) << 6) | (patch.attack[slot] & 0x1F));
			ym(tick, half, 0x60 + at,
				(patch.tremolo[slot] ? 0x80 : 0) | (patch.decay[slot] & 0x1F));
			ym(tick, half, 0x70 + at, patch.sustain[slot] & 0x1F);
			ym(tick, half, 0x80 + at,
				((patch.sustainLevel[slot] & 0x0F) << 4) | (patch.release[slot] & 0x0F));
			ym(tick, half, 0x90 + at, patch.ssg[slot] & 0x0F);
		}

		ym(tick, half, 0xB0 + channel, ((patch.feedback & 7) << 3) | (patch.algorithm & 7));
	}

	/**
		Sets a channel to a block and frequency word. The high byte is latched first, as
		the part requires, and both are written even when unchanged.

		@param tick When the write happens, in output samples from the start of the span.
		@param part Which channel the write is for.
		@param word Block and frequency packed as `wordOf` packs them.
	**/
	public function frequency(tick:Int, part:Part, word:Int):Void {
		if (!part.fm()) return;

		final held = word & 0x3FFF;
		final index = part.index();

		if (words[index] == held && whens[index] == tick) return;

		words[index] = held;
		whens[index] = tick;

		final half = halfOf(part);
		final channel = channelOf(part);

		ym(tick, half, 0xA4 + channel, (held >> 8) & 0x3F);
		ym(tick, half, 0xA0 + channel, held & 0xFF);
	}

	/**
		Writes register `$B4` whole. That register carries the stereo bits and both LFO
		sensitivities, and it has one writer for exactly that reason: two writers gave a
		pan that would not stay put and an LFO that kept restarting.

		@param tick When the write happens, in output samples from the start of the span.
		@param part Which channel the write is for.
		@param value The whole byte, stereo bits and both sensitivities.
	**/
	public function sides(tick:Int, part:Part, value:Int):Void {
		if (!part.fm()) return;

		ym(tick, halfOf(part), 0xB4 + channelOf(part), value & 0xFF);
	}

	/**
		Sets one operator total level.

		@param tick When the write happens, in output samples from the start of the span.
		@param part Which channel the write is for.
		@param slot Which operator, 0 to 3.
		@param value The attenuation, 0 loudest and 127 silent.
	**/
	public function totalLevel(tick:Int, part:Part, slot:Int, value:Int):Void {
		if (!part.fm()) return;

		final half = halfOf(part);
		final channel = channelOf(part);
		final group = slot == 1 ? 2 : (slot == 2 ? 1 : slot);

		ym(tick, half, 0x40 + group * 4 + channel, value & 0x7F);
	}

	/**
		Rewrites every carrier total level for a new velocity, leaving the modulators
		alone, which is what a velocity change during a note has to do.

		@param tick When the write happens, in output samples from the start of the span.
		@param part Which channel the write is for.
		@param patch The patch the channel is holding.
		@param velocity The new velocity, 0 to 127.
	**/
	public function level(tick:Int, part:Part, patch:Patch, velocity:Int):Void {
		if (!part.fm()) return;

		final half = halfOf(part);
		final channel = channelOf(part);

		for (group in 0...4) {
			final slot = GROUP[group];
			if (!patch.carries(slot)) continue;

			ym(tick, half, 0x40 + group * 4 + channel, levelOf(patch, slot, velocity));
		}
	}

	/**
		@param patch The patch being played.
		@param slot Which operator, 0 to 3.
		@param velocity The velocity, 0 to 127.
		@return The total level that operator should carry. A modulator keeps its own; only a
			carrier is scaled.
	**/
	public static function levelOf(patch:Patch, slot:Int, velocity:Int):Int {
		final total = patch.totalLevel[slot] & 0x7F;
		if (!patch.carries(slot)) return total;

		final quieter = total + Velocity.attenuates(velocity);
		return quieter > 127 ? 127 : quieter;
	}

	/**
		Tunes a channel to a note, whichever part it is on.

		@param tick When the write happens, in output samples from the start of the span.
		@param part Which channel the write is for.
		@param note A MIDI note number.
	**/
	public function tune(tick:Int, part:Part, note:Int):Void {
		if (!part.fm()) return;

		frequency(tick, part, wordOf(note));
	}

	/**
		Keys every operator of an FM channel on.

		@param tick When the write happens, in output samples from the start of the span.
		@param part Which channel the write is for.
	**/
	public function keyOn(tick:Int, part:Part):Void {
		if (!part.fm()) return;
		keyed[part.index()] = 1;
		ym(tick, 0, 0x28, 0xF0 | select(part));
	}

	/**
		Keys every operator of an FM channel off.

		@param tick When the write happens, in output samples from the start of the span.
		@param part Which channel the write is for.
	**/
	public function keyOff(tick:Int, part:Part):Void {
		if (!part.fm()) return;
		keyed[part.index()] = 0;
		ym(tick, 0, 0x28, select(part));
	}

	/**
		Lets an FM channel go at its quickest: every operator's release rate to 15, keeping the
		sustain level beside it, and then a key off where the channel is keyed on. The next key
		on's patch puts the release back, so this only ever shortens a note that is about to be cut
		anyway, and a channel already quiet at its quickest release costs no writes at all.

		@param tick When the write happens, in output samples from the start of the span.
		@param part Which channel the write is for.
	**/
	public function fades(tick:Int, part:Part):Void {
		if (!part.fm()) return;

		final half = halfOf(part);
		final channel = channelOf(part);

		for (group in 0...4) {
			final at = 0x80 + group * 4 + channel;
			ym(tick, half, at, (settled[(half << 8) | at] & 0xF0) | 0x0F);
		}

		if (keyed[part.index()] != 0) keyOff(tick, part);
	}

	/**
		@param part An FM channel.
		@return The channel selector byte register `$28` wants for it.
	**/
	static inline function select(part:Part):Int {
		return channelOf(part) | (part.index() >= 3 ? 4 : 0);
	}

	/**
		Tunes a square channel to a note.

		@param tick When the write happens, in output samples from the start of the span.
		@param part Which channel the write is for.
		@param note A MIDI note number.
	**/
	public function square(tick:Int, part:Part, note:Int):Void {
		if (!part.square()) return;

		final channel = part.index() - 6;
		final period = periodOf(note);

		psg(tick, 0x80 | (channel << 5) | (period & 0x0F));
		psg(tick, (period >> 4) & 0x3F);
	}

	/**
		Writes one operator register by its base, which is how automation reaches a field
		without knowing the address arithmetic.

		@param tick When the write happens, in output samples from the start of the span.
		@param part Which channel the write is for.
		@param base The register base, `$30` to `$90`.
		@param slot Which operator, 0 to 3.
		@param value The byte to write.
	**/
	public function shaping(tick:Int, part:Part, base:Int, slot:Int, value:Int):Void {
		if (!part.fm()) return;

		final half = halfOf(part);
		final channel = channelOf(part);

		if (base == 0xB0) {
			ym(tick, half, 0xB0 + channel, value & 0xFF);
			return;
		}

		final group = slot == 1 ? 2 : (slot == 2 ? 1 : slot);
		ym(tick, half, base + group * 4 + channel, value & 0xFF);
	}

	/**
		Sets a square channel period directly, as the two writes the part expects.

		@param tick When the write happens, in output samples from the start of the span.
		@param part Which channel the write is for.
		@param value The ten bit period.
	**/
	public function period(tick:Int, part:Part, value:Int):Void {
		if (!part.square()) return;

		final channel = part.index() - 6;
		final held = value & 0x3FF;

		psg(tick, 0x80 | (channel << 5) | (held & 0x0F));
		psg(tick, (held >> 4) & 0x3F);
	}

	/**
		Sets a square or noise channel attenuation.

		@param tick When the write happens, in output samples from the start of the span.
		@param part Which channel the write is for.
		@param attenuation The attenuation, 0 loudest and 15 silent.
	**/
	public function attenuate(tick:Int, part:Part, attenuation:Int):Void {
		if (!part.square() && !part.noise()) return;

		final channel = part.index() - 6;
		final held = attenuation < 0 ? 0 : (attenuation > 15 ? 15 : attenuation);

		psg(tick, 0x80 | (channel << 5) | 0x10 | held);
	}

	/**
		Sets the noise control nibble. Writing it reloads the shift register, so a burst
		starts the same way every time it is written.

		@param tick When the write happens, in output samples from the start of the span.
		@param mode The control nibble: the feedback bit and the rate.
		@param again Whether to write it even when it has not changed.
	**/
	public function noise(tick:Int, mode:Int, again:Bool = true):Void {
		final byte = 0x80 | 0x60 | (mode & 0x0F);
		if (!again && noised == byte) return;

		noised = byte;
		psg(tick, byte);
	}

	/**
		Attenuates a square channel from its envelope and the velocity.

		@param tick When the write happens, in output samples from the start of the span.
		@param part Which channel the write is for.
		@param envelope The envelope to read, or null for a flat one.
		@param velocity The velocity, 0 to 127.
		@param step How far into the envelope the note is.
	**/
	public function loudness(tick:Int, part:Part, envelope:Null<Envelope>, velocity:Int,
			step:Int):Void {
		final quiet = Velocity.quiets(velocity);
		final shaped = envelope == null || envelope.steps.length == 0 ? 0 : envelope.at(step);

		attenuate(tick, part, quiet + shaped);
	}

	/**
		Silences a part, whichever kind it is: key off and full attenuation.

		@param tick When the write happens, in output samples from the start of the span.
		@param part Which channel the write is for.
	**/
	public function silence(tick:Int, part:Part):Void {
		if (part.fm()) {
			keyOff(tick, part);
			return;
		}

		if (part.square() || part.noise()) {
			attenuate(tick, part, 15);
			return;
		}

		if (!part.sampled()) return;

		byte(tick, 0x80);
		sampling(tick, false);
	}

	/**
		Turns the sample channel on or off, which takes channel six with it.

		@param tick When the write happens, in output samples from the start of the span.
		@param on Whether the sample channel takes the channel.
	**/
	public function sampling(tick:Int, on:Bool):Void {
		ym(tick, 0, 0x2B, on ? 0x80 : 0x00);
	}

	/**
		One byte to the sample channel.

		@param tick When the write happens, in output samples from the start of the span.
		@param value The unsigned sample byte.
	**/
	public function byte(tick:Int, value:Int):Void {
		ym(tick, 0, 0x2A, value & 0xFF);
	}

	/**
		Writes register `$27`, which holds channel three mode and the timer controls.

		@param tick When the write happens, in output samples from the start of the span.
		@param value The whole byte.
	**/
	public function mode(tick:Int, value:Int):Void {
		ym(tick, 0, 0x27, value & 0xFF);
	}

	/**
		Sets one of channel three separate operator frequencies, high byte latched first.

		@param tick When the write happens, in output samples from the start of the span.
		@param slot Which of the three, 1 to 3, as the register addresses count them.
			Anything outside that is ignored.
		@param word Block and frequency packed as `wordOf` packs them.
	**/
	public function operatorFrequency(tick:Int, slot:Int, word:Int):Void {
		if (slot < 1 || slot > 3) return;

		final held = word & 0x3FFF;
		if (words[5 + slot] == held && whens[5 + slot] == tick) return;

		words[5 + slot] = held;
		whens[5 + slot] = tick;

		final at = slot - 1;

		ym(tick, 0, 0xAC + at, (held >> 8) & 0x3F);
		ym(tick, 0, 0xA8 + at, held & 0xFF);
	}

	/**
		Turns the LFO on or off and sets its rate.

		@param tick When the write happens, in output samples from the start of the span.
		@param on Whether it runs.
		@param rate The rate, 0 to 7.
	**/
	public function lfo(tick:Int, on:Bool, rate:Int):Void {
		ym(tick, 0, 0x22, (on ? 0x08 : 0) | (rate & 7));
	}

	/**
		Writes every part back to silence, which is what a stop and a seek both need.

		@param tick When the write happens, in output samples from the start of the span.
	**/
	public function reset(tick:Int):Void {
		forget();
		lfo(tick, false, 0);
		sampling(tick, false);

		for (index in 0...6) {
			final part:Part = index;
			final half = halfOf(part);
			final channel = channelOf(part);

			for (group in 0...4) ym(tick, half, 0x80 + group * 4 + channel, 0x0F);

			keyOff(tick, part);
			ym(tick, half, 0xB4 + channel, 0xC0);
		}

		for (index in 6...10) attenuate(tick, index, 15);
		noise(tick, 4);
	}
}
