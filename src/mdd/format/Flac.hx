package mdd.format;

import haxe.io.Bytes;
import haxe.io.BytesOutput;
import haxe.ds.Vector;

@:unreflective
final class Flac {
	public static inline final MARK = "fLaC";
	public static inline final BLOCK = 4096;
	public static inline final ORDERS = 5;

	static final CRC8:Vector<Int> = made8();
	static final CRC16:Vector<Int> = made16();

	static function made8():Vector<Int> {
		final held = new Vector<Int>(256);

		for (index in 0...256) {
			var value = index;

			for (bit in 0...8) {
				value = (value & 0x80) != 0 ? ((value << 1) ^ 0x07) & 0xFF
					: (value << 1) & 0xFF;
			}

			held[index] = value;
		}

		return held;
	}

	static function made16():Vector<Int> {
		final held = new Vector<Int>(256);

		for (index in 0...256) {
			var value = index << 8;

			for (bit in 0...8) {
				value = (value & 0x8000) != 0 ? ((value << 1) ^ 0x8005) & 0xFFFF
					: (value << 1) & 0xFFFF;
			}

			held[index] = value;
		}

		return held;
	}

	final out:BytesOutput = new BytesOutput();

	var held:Int = 0;
	var filled:Int = 0;

	var crc8:Int = 0;
	var crc16:Int = 0;

	public var bytes(default, null):Int = 0;

	function new() {}

	inline function byte(value:Int):Void {
		final holding = value & 0xFF;

		out.writeByte(holding);
		bytes++;

		crc8 = CRC8[(crc8 ^ holding) & 0xFF];
		crc16 = ((crc16 << 8) & 0xFFFF) ^ CRC16[((crc16 >> 8) ^ holding) & 0xFF];
	}

	function put(value:Int, width:Int):Void {
		var left = width;

		while (left > 0) {
			final room = 8 - filled;
			final take = left < room ? left : room;
			final shift = left - take;
			final part = (value >>> shift) & ((1 << take) - 1);

			held = (held << take) | part;
			filled += take;
			left -= take;

			if (filled < 8) continue;

			byte(held);
			held = 0;
			filled = 0;
		}
	}

	function zeros(count:Int):Void {
		var left = count;

		while (left > 0) {
			final take = left > 24 ? 24 : left;
			put(0, take);
			left -= take;
		}
	}

	function flush():Void {
		if (filled == 0) return;

		put(0, 8 - filled);
	}

	static inline function zigzag(value:Int):Int {
		return value < 0 ? (((-value - 1) << 1) | 1) : (value << 1);
	}

	function rice(value:Int, parameter:Int):Void {
		final folded = zigzag(value);
		final quotient = folded >>> parameter;

		zeros(quotient);
		put(1, 1);

		if (parameter > 0) put(folded & ((1 << parameter) - 1), parameter);
	}

	public static function write(samples:Vector<cpp.Float32>, frames:Int, channels:Int,
			rate:Int, depth:Int, tags:Array<String>):Bytes {
		final made = new Flac();
		return made.take(samples, frames, channels, rate, depth == 24 ? 24 : 16, tags);
	}

	function take(samples:Vector<cpp.Float32>, frames:Int, channels:Int, rate:Int,
			depth:Int, tags:Array<String>):Bytes {
		out.writeString(MARK);

		streaminfo(frames, channels, rate, depth);
		comments(tags);

		final ceiling = Wav.scale(depth) - 1;
		final floor = -ceiling - 1;

		final one = new Vector<Int>(BLOCK);
		final two = new Vector<Int>(BLOCK);

		final wide = depth >> 3;
		final raw = Bytes.alloc(frames * channels * wide);

		var at = 0;
		var number = 0;
		var written = 0;

		while (at < frames) {
			final many = frames - at < BLOCK ? frames - at : BLOCK;

			for (index in 0...many) {
				for (side in 0...channels) {
					var value = Wav.whole(samples[(at + index) * channels + side], depth);

					if (value > ceiling) value = Std.int(ceiling);
					if (value < floor) value = Std.int(floor);

					if (side == 0) one[index] = value;
					else two[index] = value;

					raw.set(written, value & 0xFF);
					raw.set(written + 1, (value >> 8) & 0xFF);
					if (wide == 3) raw.set(written + 2, (value >> 16) & 0xFF);

					written += wide;
				}
			}

			frame(number, many, channels, rate, depth, one, two);

			at += many;
			number++;
		}

		final made = out.getBytes();
		final signature = haxe.crypto.Md5.make(raw);

		made.blit(SIGNED, signature, 0, signature.length);

		return made;
	}

	public static inline final SIGNED = 26;

	function streaminfo(frames:Int, channels:Int, rate:Int, depth:Int):Void {
		out.writeByte(0x00);
		out.writeByte(0);
		out.writeByte(0);
		out.writeByte(34);

		out.writeByte((BLOCK >> 8) & 0xFF);
		out.writeByte(BLOCK & 0xFF);
		out.writeByte((BLOCK >> 8) & 0xFF);
		out.writeByte(BLOCK & 0xFF);

		for (index in 0...6) out.writeByte(0);

		out.writeByte((rate >> 12) & 0xFF);
		out.writeByte((rate >> 4) & 0xFF);
		out.writeByte((((rate & 0x0F) << 4) | (((channels - 1) & 7) << 1)
			| (((depth - 1) >> 4) & 1)) & 0xFF);
		out.writeByte(((((depth - 1) & 0x0F) << 4) | ((frames >> 32) & 0x0F)) & 0xFF);

		out.writeByte((frames >> 24) & 0xFF);
		out.writeByte((frames >> 16) & 0xFF);
		out.writeByte((frames >> 8) & 0xFF);
		out.writeByte(frames & 0xFF);

		for (index in 0...16) out.writeByte(0);
	}

	function comments(tags:Array<String>):Void {
		final maker = Bytes.ofString("md-synth-daw");
		var room = 4 + maker.length + 4;

		final held:Array<Bytes> = [];

		for (tag in tags) {
			final bytes = Bytes.ofString(tag);

			held.push(bytes);
			room += 4 + bytes.length;
		}

		out.writeByte(0x84);
		out.writeByte((room >> 16) & 0xFF);
		out.writeByte((room >> 8) & 0xFF);
		out.writeByte(room & 0xFF);

		little(maker.length);
		out.write(maker);
		little(held.length);

		for (bytes in held) {
			little(bytes.length);
			out.write(bytes);
		}
	}

	inline function little(value:Int):Void {
		out.writeByte(value & 0xFF);
		out.writeByte((value >> 8) & 0xFF);
		out.writeByte((value >> 16) & 0xFF);
		out.writeByte((value >> 24) & 0xFF);
	}

	function frame(number:Int, many:Int, channels:Int, rate:Int, depth:Int,
			one:Vector<Int>, two:Vector<Int>):Void {
		crc8 = 0;
		crc16 = 0;

		put(0x3FFE, 14);
		put(0, 1);
		put(0, 1);
		put(7, 4);
		put(0, 4);
		put(channels - 1, 4);
		put(depth == 24 ? 6 : 4, 3);
		put(0, 1);

		utf8(number);

		put(many - 1, 16);

		final was = crc8;
		flush();
		byte(was);

		subframe(one, many, depth);
		if (channels > 1) subframe(two, many, depth);

		flush();

		final sum = crc16;
		out.writeByte((sum >> 8) & 0xFF);
		out.writeByte(sum & 0xFF);
		bytes += 2;
	}

	function utf8(value:Int):Void {
		if (value < 0x80) {
			put(value, 8);
			return;
		}

		if (value < 0x800) {
			put(0xC0 | (value >> 6), 8);
			put(0x80 | (value & 0x3F), 8);
			return;
		}

		if (value < 0x10000) {
			put(0xE0 | (value >> 12), 8);
			put(0x80 | ((value >> 6) & 0x3F), 8);
			put(0x80 | (value & 0x3F), 8);
			return;
		}

		put(0xF0 | (value >> 18), 8);
		put(0x80 | ((value >> 12) & 0x3F), 8);
		put(0x80 | ((value >> 6) & 0x3F), 8);
		put(0x80 | (value & 0x3F), 8);
	}

	final residual:Vector<Int> = new Vector<Int>(BLOCK);

	function subframe(values:Vector<Int>, many:Int, depth:Int):Void {
		var flat = true;
		for (index in 1...many) if (values[index] != values[0]) flat = false;

		if (flat) {
			put(0, 1);
			put(0, 6);
			put(0, 1);
			put(values[0] & ((1 << depth) - 1), depth);
			return;
		}

		var best = -1;
		var least = 0.0;

		for (order in 0...ORDERS) {
			if (order >= many) break;

			final cost = weighed(values, many, order);
			if (best >= 0 && cost >= least) continue;

			best = order;
			least = cost;
		}

		if (best < 0) {
			put(0, 1);
			put(1, 6);
			put(0, 1);

			for (index in 0...many) put(values[index] & ((1 << depth) - 1), depth);
			return;
		}

		put(0, 1);
		put(8 | best, 6);
		put(0, 1);

		for (index in 0...best) put(values[index] & ((1 << depth) - 1), depth);

		predicted(values, many, best);
		coded(many, best);
	}

	function predicted(values:Vector<Int>, many:Int, order:Int):Void {
		for (index in order...many) {
			residual[index] = switch (order) {
				case 0: values[index];
				case 1: values[index] - values[index - 1];
				case 2: values[index] - 2 * values[index - 1] + values[index - 2];
				case 3: values[index] - 3 * values[index - 1] + 3 * values[index - 2]
					- values[index - 3];
				case _: values[index] - 4 * values[index - 1] + 6 * values[index - 2]
					- 4 * values[index - 3] + values[index - 4];
			}
		}
	}

	function weighed(values:Vector<Int>, many:Int, order:Int):Float {
		predicted(values, many, order);

		var total = 0.0;

		for (index in order...many) {
			final value = residual[index];
			total += value < 0 ? -value : value;
		}

		return total + order * 32;
	}

	function coded(many:Int, order:Int):Void {
		put(0, 2);
		put(0, 4);

		final parameter = fitted(order, many);

		put(parameter, 4);
		for (index in order...many) rice(residual[index], parameter);
	}

	function fitted(from:Int, until:Int):Int {
		var total = 0.0;
		final many = until - from;

		if (many < 1) return 0;

		for (index in from...until) {
			final value = residual[index];
			total += value < 0 ? -value : value;
		}

		final mean = total / many;
		var parameter = 0;

		while (parameter < 14 && (1 << parameter) < mean) parameter++;

		var widest = 0;

		for (index in from...until) {
			final value = residual[index];
			final much = value < 0 ? -value : value;

			if (much > widest) widest = much;
		}

		while (parameter < 14 && (widest >>> parameter) > 64) parameter++;

		return parameter;
	}
}
