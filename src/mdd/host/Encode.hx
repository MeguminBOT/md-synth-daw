package mdd.host;

@:include("encode.h")

/**
	The Ogg Vorbis and Opus encoders, compiled into the binary.

	Both write into a buffer the caller supplies rather than allocating, so an export
	has one place where the room it needs is decided.
**/
extern class Encode {
	/**
		Encodes Ogg Vorbis into a buffer.

		@param samples Interleaved samples at plus or minus one.
		@param frames How many frames.
		@param channels One or two.
		@param rate The sample rate in hertz.
		@param quality The Vorbis quality, 0 to 1.
		@param tags The metadata, one entry a line.
		@param into Where the file goes.
		@param room How much room that buffer has.
		@return How many bytes were written, or a negative number on a fault.
	**/
	@:native("mdd_encode_vorbis")
	public static function vorbis(samples:cpp.RawConstPointer<cpp.Float32>, frames:Int,
		channels:Int, rate:Int, quality:cpp.Float32, tags:cpp.ConstCharStar,
		into:cpp.RawPointer<cpp.UInt8>, room:Int):Int;

	/**
		Encodes Opus in an ogg stream into a buffer.

		@param samples Interleaved samples at plus or minus one.
		@param frames How many frames.
		@param channels One or two.
		@param rate The sample rate in hertz.
		@param bitrate The target bitrate in kilobits a second.
		@param mode The application: local listening or streaming.
		@param span The frame size in milliseconds.
		@param bitrateMode Variable, constrained variable, or fixed.
		@param tags The metadata, one entry a line.
		@param into Where the file goes.
		@param room How much room that buffer has.
		@return How many bytes were written, or a negative number on a fault.
	**/
	@:native("mdd_encode_opus")
	public static function opus(samples:cpp.RawConstPointer<cpp.Float32>, frames:Int,
		channels:Int, rate:Int, bitrate:Int, mode:Int, span:Int, bitrateMode:Int,
		tags:cpp.ConstCharStar, into:cpp.RawPointer<cpp.UInt8>, room:Int):Int;
}
