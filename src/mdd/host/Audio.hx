package mdd.host;

@:include("audio.h")

/**
	The audio device, through miniaudio.

	It is called directly rather than through a framework, because a framework is a
	place policy hides: one was found pausing the whole device on window deactivate,
	which is defensible for a game and wrong for an application whose sound is listened
	to from another window.
**/
extern class Audio {
	/**
		Opens a device.

		@param rate The rate to ask for, in hertz.
		@param period Frames per callback to ask for.
		@return The device, or null where none would open. It is opened stopped.
	**/
	@:native("mdd_audio_open")
	public static function open(rate:Int, period:Int):cpp.Star<Device>;

	/**
		Starts the device playing what has been written.

		@param device The device.
		@return Nonzero where it started.
	**/
	@:native("mdd_audio_start")
	public static function start(device:cpp.Star<Device>):Int;

	/**
		Stops it.

		@param device The device.
	**/
	@:native("mdd_audio_stop")
	public static function stop(device:cpp.Star<Device>):Void;

	/**
		Closes it and gives its memory back.

		@param device The device.
	**/
	@:native("mdd_audio_close")
	public static function close(device:cpp.Star<Device>):Void;

	/**
		@param device The device.
		@return The rate it actually opened at, which is not always the one asked for.
	**/
	@:native("mdd_audio_rate")
	public static function rate(device:cpp.Star<Device>):Int;

	/**
		@param device The device.
		@return Frames per callback.
	**/
	@:native("mdd_audio_period")
	public static function period(device:cpp.Star<Device>):Int;

	/**
		@param device The device.
		@return How many callbacks have happened.
	**/
	@:native("mdd_audio_periods")
	public static function periods(device:cpp.Star<Device>):Int;

	/**
		@param device The device.
		@return The buffer size it reports. A WASAPI device asks for more than this in its first few
			callbacks, so priming exactly this much underruns.
	**/
	@:native("mdd_audio_buffer")
	public static function buffer(device:cpp.Star<Device>):Int;

	/**
		@param device The device.
		@return What the device is called.
	**/
	@:native("mdd_audio_name")
	public static function name(device:cpp.Star<Device>):cpp.ConstCharStar;

	/**
		Puts frames into the ring the callback reads from.

		@param device The device.
		@param pairs Interleaved stereo samples.
		@param frames How many frames to write.
		@return How many were taken, which is fewer than asked where the ring filled.
	**/
	@:native("mdd_audio_write")
	public static function write(device:cpp.Star<Device>, pairs:cpp.RawConstPointer<cpp.Float32>,
		frames:Int):Int;

	/**
		@param device The device.
		@return How many frames the ring has room for.
	**/
	@:native("mdd_audio_room")
	public static function room(device:cpp.Star<Device>):Int;

	/**
		@param device The device.
		@return How many frames are waiting in it.
	**/
	@:native("mdd_audio_held")
	public static function held(device:cpp.Star<Device>):Int;

	/**
		@param device The device.
		@return How many frames the ring holds in all.
	**/
	@:native("mdd_audio_capacity")
	public static function capacity(device:cpp.Star<Device>):Int;

	/**
		@param device The device.
		@return How many times the callback found nothing to play. Anything but nought is heard.
	**/
	@:native("mdd_audio_underruns")
	public static function underruns(device:cpp.Star<Device>):Int;

	/**
		@param device The device.
		@return How many frames the callback has consumed.
	**/
	@:native("mdd_audio_taken")
	public static function taken(device:cpp.Star<Device>):Int;

	/**
		Forgets the underrun and frame counts.

		@param device The device.
	**/
	@:native("mdd_audio_forget")
	public static function forget(device:cpp.Star<Device>):Void;

	/**
		@param device The device.
		@return How far behind the device is, in seconds.
	**/
	@:native("mdd_audio_latency")
	public static function latency(device:cpp.Star<Device>):Float;
}
