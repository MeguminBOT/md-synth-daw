package mdd.host;

@:include("usage.h")

/**
	What this process is costing the machine, for the status line.
**/
extern class Usage {
	/**
		Begins measuring.
	**/
	@:native("mdd_usage_start")
	public static function start():Void;

	/**
		Stops measuring and gives back whatever it held.
	**/
	@:native("mdd_usage_stop")
	public static function stop():Void;

	/**
		@return Processor use as a fraction of one core, or a negative number where it cannot be
			measured.
	**/
	@:native("mdd_usage_cpu")
	public static function cpu():Float;

	/**
		@return Memory held, in megabytes.
	**/
	@:native("mdd_usage_ram")
	public static function ram():Float;

	/**
		The high water mark rather than what is held now. A phase that allocates and frees
		inside itself is over by the time anything asks what it cost, so the figure that
		says whether a machine can run it is this one.

		@return The most memory held at once since the process started, in megabytes, or a
			negative number where it cannot be measured.
	**/
	@:native("mdd_usage_peak")
	public static function peak():Float;

	/**
		How busy the graphics device is: for this process on Windows and Linux, and for the whole
		device on macOS, which keeps no figure for one process. Linux works it out between two
		calls, so the first answers nought.

		@return Percent, or a negative number where it cannot be measured.
	**/
	@:native("mdd_usage_gpu")
	public static function gpu():Float;

	/**
		Graphics memory this process has to itself, which is what the glyph atlases and the
		render targets sit in. Approximate: the counter is per process and what a driver
		reports against it is its own business. On macOS it is what the whole device has in use.

		@return Megabytes held, or a negative number where it cannot be measured.
	**/
	@:native("mdd_usage_vram")
	public static function vram():Float;
}
