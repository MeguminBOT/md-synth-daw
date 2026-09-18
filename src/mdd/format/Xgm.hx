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

import haxe.io.Bytes;
import haxe.io.BytesOutput;
import haxe.ds.Vector;
import mdd.play.Stream;
import mdd.song.Part;
import mdd.song.Song;
import mdd.song.Tempo;

@:unreflective

/**
	The XGM driver format: commands grouped into frames, with the samples in a bank of
	sixty three slots.

	It is a driver format rather than a log, so its timing is frame quantised where a
	VGM sample timing is not: two writes three samples apart land in the same frame.
	The format description in SGDK is ambiguous in places, and where it disagrees with
	the tool that writes the files, this follows the tool, because the tool is what
	reads them back.
**/
final class Xgm {
	/**
		The four bytes an XGM file begins with.
	**/
	public static inline final MARK = "XGM ";

	/**
		Where the sample table starts.
	**/
	public static inline final TABLE = 0x0004;

	/**
		How many sample slots the format has.
	**/
	public static inline final SLOTS = 63;

	/**
		What sample data is aligned to.
	**/
	public static inline final ALIGN = 256;
	static inline final MUSIC = 0x0108;

	/**
		The rate the driver plays samples at, in hertz. It is the driver's rate rather
		than any sample's, so whatever a slot holds is played at it, and SGDK resamples
		every wave handed to the driver to exactly this. `docs/notes/xgm.md` records
		where that is stated.
	**/
	public static inline final PCM_RATE = 14000;

	/**
		How many samples can sound at once.
	**/
	public static inline final VOICES = 4;

	/**
		The value silence is at, unsigned.
	**/
	public static inline final CENTRE = 0x80;
	static inline final READS = 1;

	/**
		How long the driver spends on one command, in stream ticks. Its loop takes one
		command a slot, and a slot is 254 cycles of the 3.58 MHz Z80 between two bytes to
		the converter, so two writes in separate commands reach the chip 71 microseconds
		apart where two inside one command are about 11 apart.
	**/
	static inline final SLOT = Tempo.TICKS * 254.0 / 3579545.0;

	/**
		Frames the driver keeps the converter switched on after the last sample has run out,
		before it gives FM6 back.
	**/
	static inline final LINGER = 3;

	/**
		Command: end the frame.
	**/
	public static inline final WAIT = 0x00;

	/**
		Command: writes to the square part.
	**/
	public static inline final PSG = 0x10;

	/**
		Command: writes to the first half of the FM registers.
	**/
	public static inline final YM_LOW = 0x20;

	/**
		Command: the same in the second half.
	**/
	public static inline final YM_HIGH = 0x30;

	/**
		Command: key on or off.
	**/
	public static inline final KEY = 0x40;

	/**
		Command: start a sample on a voice.
	**/
	public static inline final PCM = 0x50;

	/**
		Command: return to a frame.
	**/
	public static inline final LOOP = 0x7E;

	/**
		Command: the music ends here.
	**/
	public static inline final END = 0x7F;

	/**
		The version the header declares.
	**/
	public var version(default, null):Int = 1;
	var pal(default, null):Bool = false;

	/**
		Frames a second, 60 on NTSC and 50 on PAL.
	**/
	public var rate(default, null):Int = 60;
	var multi(default, null):Bool = false;

	/**
		How many bytes of samples were read.
	**/
	public var sampleBytes(default, null):Int = 0;

	/**
		How many sample slots were filled.
	**/
	public var samples(default, null):Int = 0;

	/**
		How many commands were read.
	**/
	public var commands(default, null):Int = 0;

	/**
		How many frames the music runs for.
	**/
	public var frames(default, null):Int = 0;

	/**
		How many samples were started.
	**/
	public var struck(default, null):Int = 0;

	/**
		How many were refused because every voice was busy.
	**/
	public var refused(default, null):Int = 0;

	/**
		How many commands were not understood.
	**/
	public var unknown(default, null):Int = 0;

	/**
		Which frame the music ends on, or -1 where it does not.
	**/
	public var stopped(default, null):Int = -1;

	/**
		How many times more samples were wanted than the format has slots.
	**/
	public var crowded(default, null):Int = 0;

	/**
		Which frame the loop returns to, or -1 for none.
	**/
	public var loopAt(default, null):Int = -1;

	/**
		The file, after a write.
	**/
	public var written(default, null):Null<Bytes> = null;

	/**
		The title tag.
	**/
	public var title(default, null):String = "";

	/**
		The game tag.
	**/
	public var game(default, null):String = "";

	/**
		The author tag.
	**/
	public var author(default, null):String = "";

	/**
		The release date tag.
	**/
	public var released(default, null):String = "";

	/**
		The notes tag.
	**/
	public var notes(default, null):String = "";

	final starts:Vector<Int> = new Vector<Int>(SLOTS);
	final lengths:Vector<Int> = new Vector<Int>(SLOTS);

	final voiceSample:Vector<Int> = new Vector<Int>(VOICES);
	final voiceAt:Vector<Int> = new Vector<Int>(VOICES);
	final voiceRank:Vector<Int> = new Vector<Int>(VOICES);

	var block:Null<Bytes> = null;
	var sounding:Bool = false;
	var poured:Float = 0;
	var converting:Bool = false;
	var lingers:Int = 0;

	/**
		Private: use `read` or `write`.
	**/
	function new() {
		for (index in 0...SLOTS) {
			starts[index] = -1;
			lengths[index] = 0;
		}

		for (index in 0...VOICES) {
			voiceSample[index] = -1;
			voiceAt[index] = 0;
			voiceRank[index] = 0;
		}
	}

	/**
		Reads a file and puts its writes into a stream, expanding each frame back into
		sample positions.

		@param bytes The file.
		@param into Where the register writes read out of it go.
		@return What the header and the walk found.
	**/
	public static function read(bytes:Bytes, into:Stream):Xgm {
		final made = new Xgm();
		made.take(bytes, into);

		return made;
	}

	/**
		Reads the header and the sample table, then walks the frames.

		@param bytes The file.
		@param into Where the register writes read out of it go.
	**/
	function take(bytes:Bytes, into:Stream):Void {
		if (bytes.length < MUSIC || bytes.getString(0, 4) != MARK) {
			throw "this is not an xgm file";
		}

		final held = bytes.getUInt16(0x0100);

		version = bytes.get(0x0102);

		if (version != READS) {
			throw "this is an xgm of version " + version + ", and the reader knows version "
				+ READS;
		}

		final flags = bytes.get(0x0103);

		pal = (flags & 1) != 0;
		rate = pal ? 50 : 60;
		multi = (flags & 4) != 0;

		sampleBytes = held * ALIGN;

		if (0x0104 + sampleBytes + 4 > bytes.length) throw "the sample block runs off the end";

		block = bytes.sub(0x0104, sampleBytes);

		for (index in 0...SLOTS) {
			final at = TABLE + index * 4;
			final where = bytes.getUInt16(at) * ALIGN;
			final many = bytes.getUInt16(at + 2) * ALIGN;

			if (bytes.getUInt16(at) == 0xFFFF || many <= 0) continue;
			if (where + many > sampleBytes) continue;

			starts[index] = where;
			lengths[index] = many;
			samples++;
		}

		final music = 0x0104 + sampleBytes;
		final many = bytes.getInt32(music);

		if ((flags & 2) != 0) tags(bytes, music + 4 + many);

		walk(bytes, music + 4, many < 1 ? bytes.length - music - 4 : many, into);
	}

	/**
		Reads the tag block.

		@param bytes The file.
		@param at Where the block starts.
	**/
	function tags(bytes:Bytes, at:Int):Void {
		if (at < 0 || at + 12 > bytes.length || bytes.getString(at, 4) != "Gd3 ") return;

		var pen = at + 12;
		final held:Array<String> = [];

		while (held.length < 11 && pen + 1 < bytes.length) {
			final out = new StringBuf();

			while (pen + 1 < bytes.length) {
				final code = bytes.getUInt16(pen);
				pen += 2;

				if (code == 0) break;
				out.addChar(code);
			}

			held.push(out.toString());
		}

		title = held.length > 0 ? held[0] : "";
		game = held.length > 2 ? held[2] : "";
		author = held.length > 6 ? held[6] : "";
		released = held.length > 8 ? held[8] : "";
		notes = held.length > 10 ? held[10] : "";
	}

	/**
		Walks every frame, turning each command into writes at the frame position.

		@param bytes The file.
		@param from Where the music starts.
		@param many How many bytes of it there are.
		@param into Where the register writes read out of it go.
	**/
	function walk(bytes:Bytes, from:Int, many:Int, into:Stream):Void {
		final step = Tempo.TICKS / rate;
		final ends = from + many > bytes.length ? bytes.length : from + many;

		var at = from;
		var tick = 0.0;
		var inside = 0.0;

		into.ym(0, 0, 0x2A, CENTRE);

		while (at < ends) {
			final code = bytes.get(at);
			at++;
			commands++;

			if (code == WAIT) {
				mixed(into, tick, tick + step);
				tick += step;
				inside = 0;
				frames++;
				rested(into, Math.round(tick));
				continue;
			}

			if (code == END) break;

			if (code == LOOP) {
				if (at + 3 > ends) break;

				loopAt = bytes.get(at) | (bytes.get(at + 1) << 8) | (bytes.get(at + 2) << 16);
				at += 3;
				continue;
			}

			final count = (code & 0x0F) + 1;
			final now = Math.round(tick + inside);

			inside += SLOT;

			switch (code & 0xF0) {
				case PSG:
					for (index in 0...count) {
						if (at >= ends) break;

						into.psg(now, bytes.get(at));
						at++;
					}

				case YM_LOW, YM_HIGH:
					final half = (code & 0xF0) == YM_LOW ? 0 : 1;

					for (index in 0...count) {
						if (at + 1 >= ends) break;

						into.ym(now, half, bytes.get(at), bytes.get(at + 1));
						at += 2;
					}

				case KEY:
					for (index in 0...count) {
						if (at >= ends) break;

						into.ym(now, 0, 0x28, bytes.get(at));
						at++;
					}

				case PCM:
					if (at >= ends) break;

					struck++;
					played(code & 3, (code & 0x0C) >> 2, bytes.get(at));
					at++;

				case _:
					unknown++;
					stopped = code;
					at = ends;
			}
		}

		if (sounding) into.ym(Math.round(tick), 0, 0x2A, CENTRE);
	}

	/**
		Gives FM6 back once no sample has played for `LINGER` frames, the way the driver
		switches the converter off at the end of a frame with nothing left to mix.

		@param into Where the register writes read out of it go.
		@param now Where the frame ends.
	**/
	function rested(into:Stream, now:Int):Void {
		if (sounding) {
			lingers = LINGER;
			return;
		}

		if (!converting) return;

		if (lingers > 0) {
			lingers--;
			return;
		}

		converting = false;
		into.ym(now, 0, 0x2B, 0);
	}

	/**
		Starts a sample on a voice, or refuses it where the voice is busy with a higher
		priority one.

		@param voice Which of the four voices.
		@param rank Its priority.
		@param id Which sample slot.
	**/
	function played(voice:Int, rank:Int, id:Int):Void {
		if (id == 0) {
			voiceSample[voice] = -1;
			voiceRank[voice] = 0;
			return;
		}

		final which = id - 1;
		if (which < 0 || which >= SLOTS || starts[which] < 0) return;

		if (voiceSample[voice] >= 0 && rank < voiceRank[voice]) {
			refused++;
			return;
		}

		voiceSample[voice] = which;
		voiceAt[voice] = 0;
		voiceRank[voice] = rank;
	}

	/**
		Writes the converter bytes the sounding voices produce across a span, mixed
		together the way the driver mixes them.

		@param into Where the register writes read out of it go.
		@param from The first sample of the span.
		@param until One past the last.
	**/
	function mixed(into:Stream, from:Float, until:Float):Void {
		final held = block;
		if (held == null) return;

		final step = Tempo.TICKS / PCM_RATE;

		if (poured < from) poured = from;

		while (poured < until) {
			var total = 0;
			var live = 0;

			for (voice in 0...VOICES) {
				final which = voiceSample[voice];
				if (which < 0) continue;

				final at = starts[which] + voiceAt[voice];

				if (voiceAt[voice] >= lengths[which] || at >= held.length) {
					voiceSample[voice] = -1;
					voiceRank[voice] = 0;
					continue;
				}

				final value = held.get(at);

				total += value > 127 ? value - 256 : value;
				voiceAt[voice]++;
				live++;
			}

			final now = Math.round(poured);
			poured += step;

			if (live == 0) {
				if (!sounding) continue;

				sounding = false;
				into.ym(now, 0, 0x2A, CENTRE);
				continue;
			}

			sounding = true;

			if (!converting) {
				converting = true;
				into.ym(now, 0, 0x2B, CENTRE);
			}

			final clamped = total < -128 ? -128 : (total > 127 ? 127 : total);
			into.ym(now, 0, 0x2A, clamped + 128);
		}
	}

	/**
		Writes a register stream out as an XGM file, gathering the samples its converter
		notes play into the bank.

		Writes keep the order they were made in around a key write: a register written
		after one goes into a command after it, and two key writes for one channel never
		share a command. The driver runs one command a slot, so the writes inside one
		command reach the chip closer together than it reads its key bits, and a key off
		and a key on sharing one would give the note no attack.

		@param song The song the samples come from.
		@param stream The writes to put in it.
		@param strikes The converter notes the stream was made with, the way
			`Sequencer.strikes` collects them: where each starts and ends and which
			instrument plays it.
		@param from The first sample to write.
		@param to One past the last.
		@param rate Frames a second to declare.
		@return What was written, with the file in `written`.
	**/
	public static function write(song:Song, stream:Stream, strikes:Array<Int>, from:Int, to:Int,
			rate:Int = 60):Xgm {
		final made = new Xgm();
		final bank = new Bank(song, strikes, from, rate);
		final body = new BytesOutput();

		final psg:Array<Int> = [];
		final low:Array<Int> = [];
		final high:Array<Int> = [];
		final keys:Array<Int> = [];

		var index = 0;
		var frame = 0;
		var tick = from;

		while (tick < to) {
			final ends = from + Math.round((frame + 1.0) * Tempo.TICKS / rate);

			if (ends <= tick) break;

			while (index < stream.count && stream.tickAt(index) < ends) {
				if (stream.tickAt(index) < from) {
					index++;
					continue;
				}

				if (stream.kindAt(index) == Stream.PSG) {
					psg.push(stream.valueAt(index));
					index++;
					continue;
				}

				final port = stream.portAt(index);

				if ((port & 1) != 0 || index + 1 >= stream.count) {
					index++;
					continue;
				}

				final address = stream.valueAt(index);
				final value = stream.valueAt(index + 1);

				index += 2;

				if (address == 0x2A || address == 0x2B) continue;

				if (port < 2 && address == 0x28) {
					if (keyed(keys, value)) flushed(body, psg, low, high, keys);

					keys.push(value);
					continue;
				}

				if (keys.length > 0) flushed(body, psg, low, high, keys);

				if (port < 2) {
					low.push(address);
					low.push(value);
				} else {
					high.push(address);
					high.push(value);
				}
			}

			flushed(body, psg, low, high, keys);
			bank.struck(body, frame);

			body.writeByte(WAIT);

			tick = ends;
			frame++;
		}

		body.writeByte(END);

		final music = body.getBytes();
		final held = bank.bytes();
		final tagged = tagging(song);

		final out = Bytes.alloc(MUSIC + held.length + music.length + tagged.length);

		out.blit(0, Bytes.ofString(MARK), 0, 4);

		for (slot in 0...SLOTS) {
			final at = TABLE + slot * 4;

			if (slot >= bank.count) {
				out.setUInt16(at, 0xFFFF);
				out.setUInt16(at + 2, 0x0000);
				continue;
			}

			out.setUInt16(at, Std.int(bank.startOf(slot) / ALIGN));
			out.setUInt16(at + 2, Std.int(bank.lengthOf(slot) / ALIGN));
		}

		out.setUInt16(0x0100, Std.int(held.length / ALIGN));
		out.set(0x0102, 1);
		out.set(0x0103, (rate == 50 ? 1 : 0) | (tagged.length > 0 ? 2 : 0));

		out.blit(0x0104, held, 0, held.length);
		out.setInt32(0x0104 + held.length, music.length);
		out.blit(0x0108 + held.length, music, 0, music.length);
		out.blit(MUSIC + held.length + music.length, tagged, 0, tagged.length);

		made.written = out;
		made.title = song.name;
		made.author = song.author;
		made.version = 1;
		made.pal = rate == 50;
		made.rate = rate;
		made.samples = bank.count;
		made.sampleBytes = held.length;
		made.frames = frame;
		made.struck = bank.placed;
		made.crowded = bank.crowded;
		made.refused = bank.dropped;

		return made;
	}

	/**
		Writes the tag block.

		@param song The song the tags come from.
		@return The block.
	**/
	static function tagging(song:Song):Bytes {
		if (song.name == "" && song.author == "" && song.album == "" && song.year == ""
				&& song.comment == "") {
			return Bytes.alloc(0);
		}

		final fields:Array<String> = [song.name, "", song.album, "", "", "", song.author, "",
			song.year, "", song.comment];

		final body = new BytesOutput();

		for (held in fields) {
			for (index in 0...held.length) body.writeUInt16(StringTools.fastCodeAt(held, index));
			body.writeUInt16(0);
		}

		final said = body.getBytes();
		final out = Bytes.alloc(12 + said.length);

		out.blit(0, Bytes.ofString("Gd3 "), 0, 4);
		out.setInt32(4, 0x0100);
		out.setInt32(8, said.length);
		out.blit(12, said, 0, said.length);

		return out;
	}

	/**
		Writes out what a frame has gathered since the last key write, in the order the
		driver runs it, and empties the lists for what comes after.

		@param body Where the commands go.
		@param psg Writes to the square part.
		@param low Register and value pairs to the first half of the FM registers.
		@param high The same for the second half.
		@param keys Writes to the key register.
	**/
	static function flushed(body:BytesOutput, psg:Array<Int>, low:Array<Int>, high:Array<Int>,
			keys:Array<Int>):Void {
		bytes(body, PSG, psg, 1);
		bytes(body, YM_LOW, low, 2);
		bytes(body, YM_HIGH, high, 2);
		bytes(body, KEY, keys, 1);

		psg.resize(0);
		low.resize(0);
		high.resize(0);
		keys.resize(0);
	}

	/**
		@param keys The key writes gathered for one command.
		@param value Another key write.
		@return Whether one of them is for the same channel.
	**/
	static function keyed(keys:Array<Int>, value:Int):Bool {
		for (held in keys) if ((held & 7) == (value & 7)) return true;

		return false;
	}

	/**
		Writes one command and the bytes it carries, splitting a run that is longer than
		one command can hold.

		@param body Where the command goes.
		@param code The command byte.
		@param held The bytes it carries.
		@param width How many bytes each entry takes.
	**/
	static function bytes(body:BytesOutput, code:Int, held:Array<Int>, width:Int):Void {
		var at = 0;

		while (at < held.length) {
			var many = Std.int((held.length - at) / width);
			if (many > 16) many = 16;

			body.writeByte(code | (many - 1));

			for (index in 0...many * width) body.writeByte(held[at + index] & 0xFF);
			at += many * width;
		}
	}
}

@:unreflective

/**
	The sample bank an XGM file carries: sixty three slots, each holding one sample
	aligned to a boundary, and the frames each converter note starts and stops in.

	The notes come from the sequencer rather than from a walk over the song, so a kit's
	hit is the one its key picks and a muted or silenced part sends nothing. A note is
	stopped where it ends when its sample would outlast it, because that is where the
	piece stops it.
**/
private class Bank {
	public var count(default, null):Int = 0;
	public var dropped(default, null):Int = 0;
	public var crowded(default, null):Int = 0;
	public var placed(default, null):Int = 0;

	final held:Array<Int> = [];
	final starts:Array<Int> = [];
	final lengths:Array<Int> = [];
	final named:Array<Int> = [];

	final when:Array<Int> = [];
	final until:Array<Int> = [];
	final which:Array<Int> = [];

	final free:Vector<Int> = new Vector<Int>(Xgm.VOICES);
	final due:Vector<Int> = new Vector<Int>(Xgm.VOICES);

	final rate:Int;
	final volume:Int;
	var read:Int = 0;

	/**
		@param song The song the samples come from.
		@param strikes Each converter note: where it starts and ends, in samples, and
			which instrument plays it.
		@param from The sample the file starts at.
		@param rate Frames a second.
	**/
	public function new(song:Song, strikes:Array<Int>, from:Int, rate:Int) {
		this.rate = rate < 1 ? 1 : rate;
		volume = song.volume[Part.Dac.index()];

		for (voice in 0...Xgm.VOICES) {
			free[voice] = 0;
			due[voice] = -1;
		}

		final step = Tempo.TICKS / this.rate;
		var at = 0;

		while (at + 2 < strikes.length) {
			final on = strikes[at] - from;
			final off = strikes[at + 1] - from;
			final instrument = strikes[at + 2];

			at += 3;

			if (on < 0) continue;

			final slot = slotOf(song, instrument);
			if (slot < 0) continue;

			final start = Math.floor(on / step);
			final end = Math.floor(off / step);

			when.push(start);
			until.push(end > start ? end : start + 1);
			which.push(slot);
		}

		order();
	}

	function order():Void {
		for (index in 1...when.length) {
			final at = when[index];
			final ends = until[index];
			final slot = which[index];

			var back = index - 1;

			while (back >= 0 && when[back] > at) {
				when[back + 1] = when[back];
				until[back + 1] = until[back];
				which[back + 1] = which[back];
				back--;
			}

			when[back + 1] = at;
			until[back + 1] = ends;
			which[back + 1] = slot;
		}
	}

	/**
		Finds the slot an instrument's sample is in, putting it in the bank the first
		time: resampled to the driver's rate, made signed, and scaled by the converter's
		volume the way the piece scales every byte it plays.

		@param song The song.
		@param instrument The instrument, by index.
		@return Its slot, or -1 where it has no sample or the bank is full.
	**/
	function slotOf(song:Song, instrument:Int):Int {
		for (index in 0...count) if (named[index] == instrument) return index;

		if (count >= Xgm.SLOTS) {
			dropped++;
			return -1;
		}

		final made = song.instrumentAt(instrument);
		if (made == null) return -1;

		final sample = song.sampleAt(made.sample);
		if (sample == null || sample.length() == 0) return -1;

		final rate = sample.rate < 1 ? 1 : sample.rate;
		final many = Math.round(sample.length() * Xgm.PCM_RATE / rate);
		if (many < 1) return -1;

		final start = held.length;

		for (index in 0...many) {
			var at = Math.floor(index * rate / Xgm.PCM_RATE);
			if (at >= sample.length()) at = sample.length() - 1;

			final value = (sample.bytes[at] & 0xFF) - 128;
			held.push(volume >= Song.LOUDEST ? value : Std.int(value * volume / Song.LOUDEST));
		}

		while (held.length % Xgm.ALIGN != 0) held.push(0);

		starts.push(start);
		lengths.push(held.length - start);
		named.push(instrument);

		count++;
		return count - 1;
	}

	public inline function startOf(slot:Int):Int {
		return starts[slot];
	}

	public inline function lengthOf(slot:Int):Int {
		return lengths[slot];
	}

	public function bytes():Bytes {
		final out = Bytes.alloc(held.length);
		for (index in 0...held.length) out.set(index, held[index] & 0xFF);

		return out;
	}

	inline function busy(slot:Int):Int {
		final many = Math.ceil(lengths[slot] * rate / Xgm.PCM_RATE);
		return many < 1 ? 1 : many;
	}

	/**
		Writes the commands a frame needs: a stop for each voice whose note has ended
		while its sample still plays, then a start for each note beginning.

		@param body Where the commands go.
		@param frame Which frame.
	**/
	public function struck(body:BytesOutput, frame:Int):Void {
		for (voice in 0...Xgm.VOICES) {
			if (due[voice] < 0 || due[voice] > frame) continue;

			due[voice] = -1;
			if (free[voice] <= frame) continue;

			free[voice] = frame;

			body.writeByte(Xgm.PCM | voice);
			body.writeByte(0);
		}

		while (read < when.length && when[read] <= frame) {
			final slot = which[read];
			final ends = until[read];

			read++;

			var voice = -1;

			for (index in 0...Xgm.VOICES) {
				if (free[index] > frame) continue;

				voice = index;
				break;
			}

			if (voice < 0) {
				crowded++;
				continue;
			}

			final runs = frame + busy(slot);

			free[voice] = runs;
			due[voice] = ends < runs ? ends : -1;
			placed++;

			body.writeByte(Xgm.PCM | voice);
			body.writeByte((slot + 1) & 0xFF);
		}
	}
}
