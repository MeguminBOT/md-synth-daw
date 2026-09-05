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

	final mid:Vector<Int> = new Vector<Int>(BLOCK);
	final side:Vector<Int> = new Vector<Int>(BLOCK);

	function guessed(values:Vector<Int>, many:Int):Float {
		var least = 0.0;

		for (order in 0...ORDERS) {
			if (order >= many) break;

			final cost = weighed(values, many, order);
			if (order == 0 || cost < least) least = cost;
		}

		return least;
	}

	function paired(one:Vector<Int>, two:Vector<Int>, many:Int):Int {
		for (index in 0...many) {
			mid[index] = (one[index] + two[index]) >> 1;
			side[index] = one[index] - two[index];
		}

		final left = guessed(one, many);
		final right = guessed(two, many);
		final middle = guessed(mid, many);
		final apart = guessed(side, many);

		var least = left + right;
		var mode = 1;

		if (left + apart < least) {
			least = left + apart;
			mode = 8;
		}

		if (apart + right < least) {
			least = apart + right;
			mode = 9;
		}

		if (middle + apart < least) mode = 10;

		return mode;
	}

	function frame(number:Int, many:Int, channels:Int, rate:Int, depth:Int,
			one:Vector<Int>, two:Vector<Int>):Void {
		final mode = channels == 2 ? paired(one, two, many) : channels - 1;

		crc8 = 0;
		crc16 = 0;

		put(0x3FFE, 14);
		put(0, 1);
		put(0, 1);
		put(7, 4);
		put(0, 4);
		put(mode, 4);
		put(depth == 24 ? 6 : 4, 3);
		put(0, 1);

		utf8(number);

		put(many - 1, 16);

		final was = crc8;
		flush();
		byte(was);

		switch (mode) {
			case 8:
				subframe(one, many, depth);
				subframe(side, many, depth + 1);

			case 9:
				subframe(side, many, depth + 1);
				subframe(two, many, depth);

			case 10:
				subframe(mid, many, depth);
				subframe(side, many, depth + 1);

			default:
				subframe(one, many, depth);
				if (channels > 1) subframe(two, many, depth);
		}

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

	public static inline final LPC_MOST = 12;
	public static inline final PRECISION = 15;

	final shaped:Vector<Float> = new Vector<Float>(BLOCK);
	final curve:Vector<Float> = new Vector<Float>(BLOCK);
	final auto:Vector<Float> = new Vector<Float>(LPC_MOST + 1);
	final ladder:Vector<Float> = new Vector<Float>(LPC_MOST * LPC_MOST);
	final rest:Vector<Float> = new Vector<Float>(LPC_MOST + 1);
	final weights:Vector<Float> = new Vector<Float>(LPC_MOST);
	final swap:Vector<Float> = new Vector<Float>(LPC_MOST);
	final coefficients:Vector<Int> = new Vector<Int>(LPC_MOST);

	var curved:Int = 0;

	function windowed(many:Int):Void {
		if (curved == many) return;

		for (index in 0...many) {
			curve[index] = 0.5 - 0.5 * Math.cos(2 * Math.PI * index / (many - 1));
		}

		curved = many;
	}

	function correlated(values:Vector<Int>, many:Int):Void {
		windowed(many);

		for (index in 0...many) shaped[index] = values[index] * curve[index];

		for (lag in 0...LPC_MOST + 1) {
			var total = 0.0;
			for (index in lag...many) total += shaped[index] * shaped[index - lag];

			auto[lag] = total;
		}
	}

	function laddered(most:Int):Void {
		var error = auto[0];
		rest[0] = error;

		for (order in 0...most) {
			var acc = auto[order + 1];
			for (index in 0...order) acc -= weights[index] * auto[order - index];

			final step = error == 0 ? 0.0 : acc / error;

			for (index in 0...order) swap[index] = weights[index] - step * weights[order - 1 - index];
			for (index in 0...order) weights[index] = swap[index];

			weights[order] = step;

			error *= 1 - step * step;
			if (error < 0) error = 0;

			rest[order + 1] = error;

			for (index in 0...order + 1) ladder[order * LPC_MOST + index] = weights[index];
		}
	}

	function fixedUp(order:Int):Int {
		var most = 0.0;

		for (index in 0...order) {
			final value = ladder[(order - 1) * LPC_MOST + index];
			final size = value < 0 ? -value : value;

			if (size > most) most = size;
		}

		if (most <= 0) return -1;

		var shift = PRECISION - 1 - Std.int(Math.floor(Math.log(most) / Math.log(2))) - 1;

		if (shift > 15) shift = 15;
		if (shift < 0) return -1;

		final top = (1 << (PRECISION - 1)) - 1;
		final bottom = -(1 << (PRECISION - 1));
		final scale = Math.pow(2, shift);

		var drift = 0.0;

		for (index in 0...order) {
			final want = ladder[(order - 1) * LPC_MOST + index] * scale + drift;

			var value = Math.round(want);

			if (value > top) value = top;
			if (value < bottom) value = bottom;

			drift = want - value;
			coefficients[index] = value;
		}

		return shift;
	}

	function modelled(values:Vector<Int>, many:Int, order:Int, shift:Int):Void {
		final scale = Math.pow(2, shift);

		for (index in order...many) {
			var total = 0.0;
			for (step in 0...order) total += coefficients[step] * values[index - 1 - step];

			residual[index] = values[index] - Std.int(Math.ffloor(total / scale));
		}
	}

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

		var order = 0;
		var shift = -1;
		var leastLpc = 0.0;

		if (many > LPC_MOST * 2) {
			correlated(values, many);

			if (auto[0] > 0) {
				laddered(LPC_MOST);

				for (want in 1...LPC_MOST + 1) {
					final tried = fixedUp(want);
					if (tried < 0) continue;

					modelled(values, many, want, tried);

					var total = 0.0;

					for (index in want...many) {
						final value = residual[index];
						total += value < 0 ? -value : value;
					}

					final cost = total + want * (PRECISION + depth);

					if (shift < 0 || cost < leastLpc) {
						leastLpc = cost;
						order = want;
						shift = tried;
					}
				}
			}
		}

		if (shift >= 0 && leastLpc < least) {
			put(0, 1);
			put(32 + order - 1, 6);
			put(0, 1);

			for (index in 0...order) put(values[index] & ((1 << depth) - 1), depth);

			put(PRECISION - 1, 4);
			put(shift, 5);

			fixedUp(order);

			for (index in 0...order) {
				put(coefficients[index] & ((1 << PRECISION) - 1), PRECISION);
			}

			modelled(values, many, order, shift);
			coded(many, order);

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

	static inline final MOST_PARTS = 6;
	static inline final MOST_RICE = 14;

	final sums:Vector<Float> = new Vector<Float>(1 << MOST_PARTS);

	function coded(many:Int, order:Int):Void {
		var most = 0;

		while (most < MOST_PARTS && (many & ((1 << (most + 1)) - 1)) == 0
			&& (many >> (most + 1)) > order) most++;

		gathered(many, order, most);

		var bestOrder = 0;
		var least = 0.0;

		for (level in 0...most + 1) {
			final cost = costed(many, order, level);

			if (level == 0 || cost < least) {
				least = cost;
				bestOrder = level;
			}
		}

		put(0, 2);
		put(bestOrder, 4);

		final parts = 1 << bestOrder;
		final each = many >> bestOrder;

		for (index in 0...parts) {
			final from = index == 0 ? order : index * each;
			final until = (index + 1) * each;

			final parameter = fitted(from, until);

			put(parameter, 4);
			for (at in from...until) rice(residual[at], parameter);
		}
	}

	function gathered(many:Int, order:Int, most:Int):Void {
		final parts = 1 << most;
		final each = many >> most;

		for (index in 0...parts) {
			final from = index == 0 ? order : index * each;
			final until = (index + 1) * each;

			var total = 0.0;
			for (at in from...until) total += zigzag(residual[at]);

			sums[index] = total;
		}
	}

	function costed(many:Int, order:Int, level:Int):Float {
		final parts = 1 << level;
		final each = many >> level;
		final gather = 1 << (MOST_PARTS - level);

		var total = 0.0;

		for (index in 0...parts) {
			var held = 0.0;
			for (step in 0...gather) held += sums[index * gather + step];

			final count = index == 0 ? each - order : each;

			total += 4 + priced(held, count);
		}

		return total;
	}

	static function priced(total:Float, count:Int):Float {
		if (count < 1) return 0;

		var least = 0.0;

		for (parameter in 0...MOST_RICE + 1) {
			final cost = count * (1 + parameter) + total / (1 << parameter);
			if (parameter == 0 || cost < least) least = cost;
		}

		return least;
	}

	function fitted(from:Int, until:Int):Int {
		final count = until - from;
		if (count < 1) return 0;

		var total = 0.0;
		for (index in from...until) total += zigzag(residual[index]);

		var best = 0;
		var least = 0.0;

		for (parameter in 0...MOST_RICE + 1) {
			final cost = count * (1 + parameter) + total / (1 << parameter);

			if (parameter == 0 || cost < least) {
				least = cost;
				best = parameter;
			}
		}

		return best;
	}
}
