package mdd.format;

import haxe.io.Bytes;
import haxe.io.BytesOutput;
import haxe.ds.Vector;
import mdd.play.Stream;

@:unreflective
final class Vgm {
	public static inline final MARK = "Vgm ";
	public static inline final HEADER = 0x40;
	public static inline final TICKS = 44100;

	public static inline final PSG = 0x50;
	public static inline final YM_LOW = 0x52;
	public static inline final YM_HIGH = 0x53;
	public static inline final WAIT = 0x61;
	public static inline final WAIT_60 = 0x62;
	public static inline final WAIT_50 = 0x63;
	public static inline final END = 0x66;
	public static inline final BLOCK = 0x67;
	public static inline final SEEK = 0xE0;
	public static inline final STEREO = 0x4F;

	public var version(default, null):Int = 0x150;
	public var snClock(default, null):Int = 0;
	public var ymClock(default, null):Int = 0;
	public var samples(default, null):Int = 0;
	public var loopAt(default, null):Int = -1;
	public var loopSamples(default, null):Int = 0;
	public var rate(default, null):Int = 60;

	public var title(default, null):String = "";
	public var game(default, null):String = "";
	public var author(default, null):String = "";
	public var released(default, null):String = "";
	public var notes(default, null):String = "";

	public var commands(default, null):Int = 0;
	public var waits(default, null):Int = 0;
	public var blocks(default, null):Int = 0;
	public var blockBytes(default, null):Int = 0;
	public var seeks(default, null):Int = 0;
	public var stereo(default, null):Int = 0;
	public var unknown(default, null):Int = 0;

	public var loopWrite(default, null):Int = -1;

	public function new() {}

	public static function read(bytes:Bytes, into:Stream):Vgm {
		final vgm = new Vgm();
		vgm.take(bytes, into);
		return vgm;
	}

	function take(bytes:Bytes, into:Stream):Void {
		if (bytes.length < HEADER || bytes.getString(0, 4) != MARK) {
			throw "not a vgm: the first four bytes are not '" + MARK + "'";
		}

		version = bytes.getInt32(0x08);
		snClock = bytes.getInt32(0x0C);
		samples = bytes.getInt32(0x18);

		final loopOffset = bytes.getInt32(0x1C);
		loopAt = loopOffset == 0 ? -1 : loopOffset + 0x1C;
		loopSamples = bytes.getInt32(0x20);
		rate = bytes.getInt32(0x24);

		ymClock = version >= 0x110 ? bytes.getInt32(0x2C) : 0;

		final gd3 = bytes.getInt32(0x14);
		if (gd3 != 0) tags(bytes, gd3 + 0x14);

		var at = HEADER;
		if (version >= 0x150) {
			final given = bytes.getInt32(0x34);
			if (given != 0) at = given + 0x34;
		}

		walk(bytes, at, into);
	}

	function tags(bytes:Bytes, at:Int):Void {
		if (at + 12 > bytes.length || bytes.getString(at, 4) != "Gd3 ") return;

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

	function walk(bytes:Bytes, from:Int, into:Stream):Void {
		var at = from;
		var tick = 0;

		while (at < bytes.length) {
			if (loopAt >= 0 && at >= loopAt && loopWrite < 0) loopWrite = into.count;

			final code = bytes.get(at);
			at++;
			commands++;

			switch (code) {
				case PSG:
					into.raw(tick, Stream.PSG, 0, bytes.get(at));
					at++;

				case YM_LOW:
					into.raw(tick, Stream.YM, 0, bytes.get(at));
					into.raw(tick, Stream.YM, 1, bytes.get(at + 1));
					at += 2;

				case YM_HIGH:
					into.raw(tick, Stream.YM, 2, bytes.get(at));
					into.raw(tick, Stream.YM, 3, bytes.get(at + 1));
					at += 2;

				case WAIT:
					tick += bytes.getUInt16(at);
					at += 2;
					waits++;

				case WAIT_60:
					tick += 735;
					waits++;

				case WAIT_50:
					tick += 882;
					waits++;

				case END:
					samples = samples == 0 ? tick : samples;
					return;

				case BLOCK:
					at++;
					final kind = bytes.get(at);
					at++;
					final length = bytes.getInt32(at);
					at += 4;

					blocks++;
					blockBytes += length;
					pcm(bytes, at, length, kind);
					at += length;

				case STEREO:
					at++;
					stereo++;

				case _:
					if (code >= 0x70 && code <= 0x7F) {
						tick += (code & 0x0F) + 1;
						waits++;
					} else if (code >= 0x80 && code <= 0x8F) {
						into.raw(tick, Stream.YM, 0, 0x2A);
						into.raw(tick, Stream.YM, 1, sampleByte());
						tick += code & 0x0F;
					} else if (code == SEEK) {
						seekTo(bytes.getInt32(at));
						at += 4;
						seeks++;
					} else {
						at += skip(code);
						unknown++;
					}
			}
		}
	}

	static function skip(code:Int):Int {
		if (code >= 0x30 && code <= 0x3F) return 1;
		if (code >= 0x40 && code <= 0x4E) return 2;
		if (code >= 0x51 && code <= 0x5F) return 2;
		if (code >= 0xA0 && code <= 0xBF) return 2;
		if (code >= 0xC0 && code <= 0xDF) return 3;
		if (code >= 0xE1 && code <= 0xFF) return 4;
		return 0;
	}

	public var pcmBytes(default, null):Vector<Int> = new Vector<Int>(0);

	var pcmHeld:Int = 0;
	var pcmAt:Int = 0;

	function pcm(bytes:Bytes, at:Int, length:Int, kind:Int):Void {
		if (kind != 0) return;

		final want = pcmHeld + length;
		final grown = new Vector<Int>(want);

		Vector.blit(pcmBytes, 0, grown, 0, pcmHeld);
		for (i in 0...length) grown[pcmHeld + i] = bytes.get(at + i);

		pcmBytes = grown;
		pcmHeld = want;
	}

	function seekTo(where:Int):Void {
		pcmAt = where;
	}

	function sampleByte():Int {
		if (pcmAt < 0 || pcmAt >= pcmHeld) return 0x80;

		final value = pcmBytes[pcmAt];
		pcmAt++;
		return value;
	}

	public static function write(stream:Stream, from:Int, to:Int, rate:Int = 60,
			title:String = "", author:String = ""):Bytes {
		final body = new BytesOutput();
		var tick = from;

		for (index in 0...stream.count) {
			final at = stream.tickAt(index);
			if (at < from || at >= to) continue;

			var waiting = at - tick;

			while (waiting > 0) {
				if (waiting > 65535) {
					body.writeByte(WAIT);
					body.writeUInt16(65535);
					waiting -= 65535;
					continue;
				}

				if (waiting <= 16) {
					body.writeByte(0x70 + waiting - 1);
					waiting = 0;
					continue;
				}

				body.writeByte(WAIT);
				body.writeUInt16(waiting);
				waiting = 0;
			}

			tick = at;

			if (stream.kindAt(index) == Stream.PSG) {
				body.writeByte(PSG);
				body.writeByte(stream.valueAt(index));
				continue;
			}

			final port = stream.portAt(index);
			if ((port & 1) != 0) continue;

			body.writeByte(port < 2 ? YM_LOW : YM_HIGH);
			body.writeByte(stream.valueAt(index));
			body.writeByte(index + 1 < stream.count ? stream.valueAt(index + 1) : 0);
		}

		var waiting = to - tick;

		while (waiting > 0) {
			final step = waiting > 65535 ? 65535 : waiting;
			body.writeByte(WAIT);
			body.writeUInt16(step);
			waiting -= step;
		}

		body.writeByte(END);

		final made = body.getBytes();
		final tagged = tagging(title, author);
		final out = Bytes.alloc(HEADER + made.length + tagged.length);

		out.blit(HEADER, made, 0, made.length);
		out.blit(HEADER + made.length, tagged, 0, tagged.length);
		out.blit(0, Bytes.ofString(MARK), 0, 4);

		if (tagged.length > 0) out.setInt32(0x14, HEADER + made.length - 0x14);

		out.setInt32(0x04, HEADER + made.length + tagged.length - 4);
		out.setInt32(0x08, 0x150);
		out.setInt32(0x0C, mdd.chip.Sn76489.CLOCK);
		out.setInt32(0x18, to - from);
		out.setInt32(0x24, rate);
		out.setInt32(0x28, 0x0009);
		out.setInt32(0x2C, mdd.chip.Ym2612.CLOCK);
		out.setInt32(0x34, HEADER - 0x34);

		return out;
	}

	static function tagging(title:String, author:String):Bytes {
		if (title == "" && author == "") return Bytes.alloc(0);

		final fields:Array<String> = [title, "", "", "", "", "", author, "", "", "", ""];
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
}
