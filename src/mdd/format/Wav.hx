package mdd.format;

import haxe.ds.Vector;
import haxe.io.Bytes;
import haxe.io.BytesOutput;

@:unreflective

/**
	Reads and writes RIFF wave files.

	It is the plain format everything else is checked against: an encoder is believed
	when what it writes decodes to the same samples this wrote.
**/
final class Wav {
	/**
		The rate of the file that was read.
	**/
	public var rate(default, null):Int = 44100;

	/**
		How many channels it carried.
	**/
	public var channels(default, null):Int = 1;

	/**
		How many frames it carried.
	**/
	public var frames(default, null):Int = 0;

	/**
		The audio, interleaved, at plus or minus one.
	**/
	public var samples(default, null):Vector<Float> = new Vector<Float>(0);

	public function new() {}

	/**
		@param depth Bits per sample.
		@return What a whole numbered sample of that depth is divided by to reach plus or minus one.
	**/
	public static inline function scale(depth:Int):Float {
		return depth == 24 ? 8388608.0 : 32768.0;
	}

	/**
		@param value A whole numbered sample.
		@param depth Bits per sample.
		@return It as a number between plus and minus one.
	**/
	public static inline function floated(value:Int, depth:Int):Float {
		return value / scale(depth);
	}

	/**
		@param value A sample between plus and minus one.
		@param depth Bits per sample.
		@return It as a whole numbered sample of that depth, clamped.
	**/
	public static inline function whole(value:Float, depth:Int):Int {
		final ceiling = scale(depth);
		final held = Math.round(value * ceiling);

		final most = Std.int(ceiling) - 1;
		final least = -Std.int(ceiling);

		return held > most ? most : (held < least ? least : held);
	}

	/**
		Reads a wave file.

		@param bytes The file.
		@return What it held. A file that will not read comes back empty rather than throwing.
	**/
	public static function read(bytes:Bytes):Wav {
		final wav = new Wav();
		wav.take(bytes);
		return wav;
	}

	/**
		Walks the chunks of a file and keeps the format and the audio.

		@param bytes The file.
	**/
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
				samples[i] = floated(value >= 0x8000 ? value - 0x10000 : value, 16);
				continue;
			}

			final value = bytes.getInt32(where);
			samples[i] = value / 2147483648.0;
		}
	}

	/**
		@return The audio as one channel, averaging the sides where there are two.
	**/
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

	/**
		Resamples the audio to a rate and reduces it to the unsigned bytes the sample
		channel takes.

		The rate change is band limited, so nothing above the new half rate folds back
		into what is kept. `Resampler` says why that matters.

		@param into The rate to resample to, in hertz.
		@return The bytes.
	**/
	public function bytes(into:Int):Vector<Int> {
		final held = into <= 0 || rate <= 0 ? mono() : Resampler.into(mono(), rate, into);
		final out = new Vector<Int>(held.length < 1 ? 1 : held.length);

		for (i in 0...held.length) {
			final value = Math.round(held[i] * 127) + 128;
		out[i] = value < 0 ? 0 : (value > 255 ? 255 : value);
		}

		return out;
	}

	/**
		Writes a wave file.

		@param samples The audio, interleaved, at plus or minus one.
		@param frames How many frames it holds.
		@param channels One or two.
		@param rate The sample rate in hertz.
		@param depth Bits per sample: 16, 24, or 32 for floating point.
		@param dither Whether to dither on the way down to whole numbers.
		@return The file.
	**/
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

			var scaled = value;

			if (dither) {
				seed = seed * 1103515245 + 12345;
				final one = ((seed >>> 16) & 0x7FFF) / 32767.0;

				seed = seed * 1103515245 + 12345;
				final two = ((seed >>> 16) & 0x7FFF) / 32767.0;

				scaled += (one - two) / scale(depth);
			}

			final held = whole(scaled, depth);

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
