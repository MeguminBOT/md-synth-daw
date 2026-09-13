package mdd.format;

import haxe.io.Bytes;
import haxe.ds.Vector;
import mdd.host.Encode;

@:unreflective

/**
	Ogg Vorbis and Opus, through the encoders compiled into the binary.

	The whole of the glue is in `src/mdd/native/encode.cpp`: it builds the header
	packets, feeds the encoder and frames the packets into ogg pages. This is the Haxe
	side of that.
**/
final class Coded {
	/**
		How much room to leave above the sample count for headers and framing.
	**/
	public static inline final SPARE = 1 << 17;

	/**
		The rate Opus works at. Granule positions in an Ogg Opus stream are always counted
		at this rate whatever the source was.
	**/
	public static inline final OPUS_RATE = 48000;

	/**
		The Vorbis quality settings on offer.
	**/
	public static final QUALITIES:Array<Float> = [0.2, 0.4, 0.6, 0.8, 1.0];

	/**
		The Opus bitrates on offer, in kilobits a second.
	**/
	public static final BITRATES:Array<Int> = [96, 128, 160, 192, 256, 384];

	/**
		Encodes Ogg Vorbis.

		@param samples The audio, interleaved, at plus or minus one.
		@param frames How many frames it holds.
		@param channels One or two.
		@param rate The sample rate in hertz.
		@param quality The Vorbis quality, 0 to 1.
		@param tags The metadata, each entry a name and a value separated by an equals sign.
		@return The file. Throws where the encoder would not run.
	**/
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

	/**
		Encodes Opus in an ogg stream.

		@param samples The audio, interleaved, at plus or minus one.
		@param frames How many frames it holds.
		@param channels One or two.
		@param rate The sample rate in hertz.
		@param bitrate The target bitrate in kilobits a second.
		@param mode The application: 0 for local listening and 1 for streaming.
		@param span The frame size in milliseconds.
		@param bitrateMode Variable, constrained variable, or fixed.
		@param tags The metadata, each entry a name and a value separated by an equals sign.
		@return The file. Throws where the encoder would not run.
	**/
	public static function opus(samples:Vector<cpp.Float32>, frames:Int, channels:Int,
			rate:Int, bitrate:Int, mode:Int, span:Int, bitrateMode:Int, tags:Array<String>):Bytes {
		final room = frames * channels * 2 + SPARE;
		final into = Bytes.alloc(room);

		final many = Encode.opus(cpp.Pointer.arrayElem(samples.toData(), 0).constRaw,
			frames, channels, rate, bitrate, mode, span, bitrateMode, tags.join("\n"),
			cpp.Pointer.arrayElem(into.getData(), 0).raw, room);

		if (many <= 0) throw "the opus encoder would not run, " + many;

		return into.sub(0, many);
	}
}
