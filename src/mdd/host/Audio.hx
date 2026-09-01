package mdd.host;

@:include("audio.h")
extern class Audio {
	@:native("mdd_audio_open")
	public static function open(rate:Int, period:Int):cpp.Star<Device>;

	@:native("mdd_audio_start")
	public static function start(device:cpp.Star<Device>):Int;

	@:native("mdd_audio_stop")
	public static function stop(device:cpp.Star<Device>):Void;

	@:native("mdd_audio_close")
	public static function close(device:cpp.Star<Device>):Void;

	@:native("mdd_audio_rate")
	public static function rate(device:cpp.Star<Device>):Int;

	@:native("mdd_audio_period")
	public static function period(device:cpp.Star<Device>):Int;

	@:native("mdd_audio_periods")
	public static function periods(device:cpp.Star<Device>):Int;

	@:native("mdd_audio_buffer")
	public static function buffer(device:cpp.Star<Device>):Int;

	@:native("mdd_audio_name")
	public static function name(device:cpp.Star<Device>):cpp.ConstCharStar;

	@:native("mdd_audio_write")
	public static function write(device:cpp.Star<Device>, pairs:cpp.RawConstPointer<cpp.Float32>,
		frames:Int):Int;

	@:native("mdd_audio_room")
	public static function room(device:cpp.Star<Device>):Int;

	@:native("mdd_audio_held")
	public static function held(device:cpp.Star<Device>):Int;

	@:native("mdd_audio_capacity")
	public static function capacity(device:cpp.Star<Device>):Int;

	@:native("mdd_audio_underruns")
	public static function underruns(device:cpp.Star<Device>):Int;

	@:native("mdd_audio_taken")
	public static function taken(device:cpp.Star<Device>):Int;

	@:native("mdd_audio_forget")
	public static function forget(device:cpp.Star<Device>):Void;

	@:native("mdd_audio_latency")
	public static function latency(device:cpp.Star<Device>):Float;
}
