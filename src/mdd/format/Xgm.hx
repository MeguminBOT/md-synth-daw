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

		into.ym(0, 0, 0x2B, CENTRE);
		into.ym(0, 0, 0x2A, CENTRE);

		while (at < ends) {
			final code = bytes.get(at);
			at++;
			commands++;

			if (code == WAIT) {
				mixed(into, tick, tick + step);
				tick += step;
				frames++;
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
			final now = Math.round(tick);

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

			final clamped = total < -128 ? -128 : (total > 127 ? 127 : total);
			into.ym(now, 0, 0x2A, clamped + 128);
		}
	}

	/**
		Writes a register stream out as an XGM file, gathering the samples it uses into
		the bank.

		@param song The song the samples come from.
		@param stream The writes to put in it.
		@param from The first sample to write.
		@param to One past the last.
		@param rate Frames a second to declare.
		@return What was written, with the file in `written`.
	**/
	public static function write(song:Song, stream:Stream, from:Int, to:Int,
			rate:Int = 60):Xgm {
		final made = new Xgm();
		final bank = new Bank(song, rate);
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

			psg.resize(0);
			low.resize(0);
			high.resize(0);
			keys.resize(0);

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

				if (port < 2) {
					if (address == 0x28) keys.push(value);
					else {
						low.push(address);
						low.push(value);
					}

					continue;
				}

				high.push(address);
				high.push(value);
			}

			bytes(body, PSG, psg, 1);
			bytes(body, YM_LOW, low, 2);
			bytes(body, YM_HIGH, high, 2);
			bytes(body, KEY, keys, 1);

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
		if (song.name == "" && song.author == "") return Bytes.alloc(0);

		final fields:Array<String> = [song.name, "", "", "", "", "", song.author, "",
			"", "", ""];

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
	aligned to a boundary.
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
	final which:Array<Int> = [];

	final free:Vector<Int> = new Vector<Int>(Xgm.VOICES);

	final rate:Int;
	var read:Int = 0;

	public function new(song:Song, rate:Int) {
		this.rate = rate < 1 ? 1 : rate;

		for (voice in 0...Xgm.VOICES) free[voice] = 0;

		if (!song.audible(Part.Dac)) {
			order();
			return;
		}

		final step = Tempo.TICKS / this.rate;
		final racked = song.rack[Part.Dac.index()];

		for (track in song.tracks) {
			if (track.muted) continue;

			for (clip in track.clips) {
				final pattern = song.patternAt(clip.pattern);
				if (pattern == null) continue;

				for (note in pattern.lane(Part.Dac).notes) {
					final at = clip.origin() + note.at;
					if (at >= clip.ends() || at < clip.at) continue;

					final slot = slotOf(song, note.instrument >= 0 ? note.instrument : racked);
					if (slot < 0) continue;

					when.push(Math.floor(song.tempo.samplesAt(at) / step));
					which.push(slot);
				}
			}
		}

		order();
	}

	function order():Void {
		for (index in 1...when.length) {
			final at = when[index];
			final held = which[index];

			var back = index - 1;

			while (back >= 0 && when[back] > at) {
				when[back + 1] = when[back];
				which[back + 1] = which[back];
				back--;
			}

			when[back + 1] = at;
			which[back + 1] = held;
		}
	}

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

			held.push((sample.bytes[at] & 0xFF) - 128);
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

	public function struck(body:BytesOutput, frame:Int):Void {
		while (read < when.length && when[read] <= frame) {
			final slot = which[read];
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

			free[voice] = frame + busy(slot);
			placed++;

			body.writeByte(Xgm.PCM | voice);
			body.writeByte((slot + 1) & 0xFF);
		}
	}
}
