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

	public function bytes(rate:Int, root:Int):Vector<Int> {
		final held = mono();
		final out = new Vector<Int>(held.length);

		for (i in 0...held.length) {
			final value = Math.round(held[i] * 127) + 128;
			out[i] = value < 0 ? 0 : (value > 255 ? 255 : value);
		}

		return out;
	}

	public static function write(samples:Vector<cpp.Float32>, frames:Int, channels:Int,
			rate:Int):Bytes {
		final out = new BytesOutput();
		final body = frames * channels * 2;

		out.writeString("RIFF");
		out.writeInt32(36 + body);
		out.writeString("WAVE");
		out.writeString("fmt ");
		out.writeInt32(16);
		out.writeUInt16(1);
		out.writeUInt16(channels);
		out.writeInt32(rate);
		out.writeInt32(rate * channels * 2);
		out.writeUInt16(channels * 2);
		out.writeUInt16(16);
		out.writeString("data");
		out.writeInt32(body);

		for (i in 0...frames * channels) {
			final value = Math.round(samples[i] * 32767);
			out.writeInt16(value > 32767 ? 32767 : (value < -32768 ? -32768 : value));
		}

		return out.getBytes();
	}
}
