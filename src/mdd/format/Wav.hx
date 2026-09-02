package mdd.format;

import haxe.ds.Vector;
import haxe.io.Bytes;
import haxe.io.BytesOutput;

@:unreflective
final class Wav {
	public var rate(default, null):Int = 44100;
	public var channels(default, null):Int = 1;
	public var frames(default, null):Int = 0;

	public var samples(default, null):Vector<Float> = new Vector<Float>(0);

	public function new() {}

	public static function read(bytes:Bytes):Wav {
		final wav = new Wav();
		wav.take(bytes);
		return wav;
	}

	function take(bytes:Bytes):Void {
		if (bytes.length < 44 || bytes.getString(0, 4) != "RIFF"
				|| bytes.getString(8, 4) != "WAVE") {
			throw "not a wav: the riff and wave marks are not there";
		}

		var at = 12;
		var bits = 16;
		var format = 1;
		var body = -1;
		var length = 0;

		while (at + 8 <= bytes.length) {
			final tag = bytes.getString(at, 4);
			final size = bytes.getInt32(at + 4);
			at += 8;

			if (size < 0 || at + size > bytes.length) break;

			if (tag == "fmt ") {
				format = bytes.getUInt16(at);
				channels = bytes.getUInt16(at + 2);
				rate = bytes.getInt32(at + 4);
				bits = bytes.getUInt16(at + 14);
			} else if (tag == "data") {
				body = at;
				length = size;
			}

			at += size + (size & 1);
		}

		if (body < 0) throw "not a wav: it carries no data chunk";
		if (channels < 1) channels = 1;

		final wide = Std.int(bits / 8);
		if (wide < 1) throw "not a wav: it says " + bits + " bits a sample";

		frames = Std.int(length / (wide * channels));
		samples = new Vector<Float>(frames * channels);

		for (i in 0...frames * channels) {
			final where = body + i * wide;

			if (format == 3 && wide == 4) {
				samples[i] = bytes.getFloat(where);
				continue;
			}

			if (wide == 1) {
				samples[i] = (bytes.get(where) - 128) / 128.0;
				continue;
			}

			if (wide == 2) {
				final value = bytes.getUInt16(where);
				samples[i] = (value >= 0x8000 ? value - 0x10000 : value) / 32768.0;
				continue;
			}

			final value = bytes.getInt32(where);
			samples[i] = value / 2147483648.0;
		}
	}

	public function mono():Vector<Float> {
		if (channels == 1) return samples;

		final out = new Vector<Float>(frames);

		for (i in 0...frames) {
			var sum = 0.0;
			for (c in 0...channels) sum += samples[i * channels + c];
			out[i] = sum / channels;
		}

		return out;
	}

	public function bytes(into:Int):Vector<Int> {
		final held = mono();
		final step = into <= 0 || rate <= 0 ? 1.0 : rate / into;
		final many = step <= 0 ? held.length : Std.int(held.length / step);
		final out = new Vector<Int>(many < 1 ? 1 : many);

		for (i in 0...out.length) {
			final at = Std.int(i * step);
			final sample = at < held.length ? held[at] : 0.0;
			final value = Math.round(sample * 127) + 128;

			out[i] = value < 0 ? 0 : (value > 255 ? 255 : value);
		}

		return out;
	}

	public static function write(samples:Vector<cpp.Float32>, frames:Int, channels:Int,
			rate:Int, depth:Int = 16, dither:Bool = false):Bytes {
		final out = new BytesOutput();
		final wide = depth == 32 ? 4 : (depth == 24 ? 3 : 2);
		final floating = depth == 32;
		final body = frames * channels * wide;

		out.writeString("RIFF");
		out.writeInt32(36 + body);
		out.writeString("WAVE");
		out.writeString("fmt ");
		out.writeInt32(16);
		out.writeUInt16(floating ? 3 : 1);
		out.writeUInt16(channels);
		out.writeInt32(rate);
		out.writeInt32(rate * channels * wide);
		out.writeUInt16(channels * wide);
		out.writeUInt16(depth);
		out.writeString("data");
		out.writeInt32(body);

		var seed = 0x12345678;

		for (index in 0...frames * channels) {
			final value = samples[index];

			if (floating) {
				out.writeFloat(value);
				continue;
			}

			final ceiling = depth == 24 ? 8388607.0 : 32767.0;
			var scaled = value * ceiling;

			if (dither) {
				seed = seed * 1103515245 + 12345;
				final one = ((seed >>> 16) & 0x7FFF) / 32767.0;

				seed = seed * 1103515245 + 12345;
				final two = ((seed >>> 16) & 0x7FFF) / 32767.0;

				scaled += one - two;
			}

			var held = Math.round(scaled);

			if (held > ceiling) held = Std.int(ceiling);
			if (held < -ceiling - 1) held = Std.int(-ceiling - 1);

			if (depth == 24) {
				out.writeByte(held & 0xFF);
				out.writeByte((held >> 8) & 0xFF);
				out.writeByte((held >> 16) & 0xFF);
				continue;
			}

			out.writeInt16(held);
		}

		return out.getBytes();
	}
}
