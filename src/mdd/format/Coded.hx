package mdd.format;

import haxe.io.Bytes;
import haxe.ds.Vector;
import mdd.host.Encode;

@:unreflective
final class Coded {
	public static inline final SPARE = 1 << 17;
	public static inline final OPUS_RATE = 48000;

	public static final QUALITIES:Array<Float> = [0.2, 0.4, 0.6, 0.8, 1.0];
	public static final BITRATES:Array<Int> = [96, 128, 160, 192, 256];

	public static function vorbis(samples:Vector<cpp.Float32>, frames:Int, channels:Int,
			rate:Int, quality:Float, tags:Array<String>):Bytes {
		final room = frames * channels * 2 + SPARE;
		final into = Bytes.alloc(room);

		final many = Encode.vorbis(cpp.Pointer.arrayElem(samples.toData(), 0).constRaw,
			frames, channels, rate, quality, tags.join("\n"),
			cpp.Pointer.arrayElem(into.getData(), 0).raw, room);

		if (many <= 0) throw "the vorbis encoder would not run, " + many;

		return into.sub(0, many);
	}

	public static function opus(samples:Vector<cpp.Float32>, frames:Int, channels:Int,
			rate:Int, bitrate:Int, tags:Array<String>):Bytes {
		final room = frames * channels * 2 + SPARE;
		final into = Bytes.alloc(room);

		final many = Encode.opus(cpp.Pointer.arrayElem(samples.toData(), 0).constRaw,
			frames, channels, rate, bitrate, tags.join("\n"),
			cpp.Pointer.arrayElem(into.getData(), 0).raw, room);

		if (many <= 0) throw "the opus encoder would not run, " + many;

		return into.sub(0, many);
	}
}
