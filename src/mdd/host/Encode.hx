package mdd.host;

@:include("encode.h")
extern class Encode {
	@:native("mdd_encode_vorbis")
	public static function vorbis(samples:cpp.RawConstPointer<cpp.Float32>, frames:Int,
		channels:Int, rate:Int, quality:cpp.Float32, tags:cpp.ConstCharStar,
		into:cpp.RawPointer<cpp.UInt8>, room:Int):Int;

	@:native("mdd_encode_opus")
	public static function opus(samples:cpp.RawConstPointer<cpp.Float32>, frames:Int,
		channels:Int, rate:Int, bitrate:Int, mode:Int, span:Int, bitrateMode:Int,
		tags:cpp.ConstCharStar, into:cpp.RawPointer<cpp.UInt8>, room:Int):Int;
}
