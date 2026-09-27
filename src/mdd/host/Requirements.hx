package mdd.host;

@:include("requirements.h")

/**
	What this machine offers the interface, written for the Windows installer to hold against what
	the application needs before it installs anything.
**/
extern class Requirements {
	/**
		Writes it to a file, one fact a line, a name and then what the machine has: every renderer
		the application offers with the level it reaches, `0` where it cannot be made, and the
		graphics memory the card can use. Starts SDL and shuts it down again, so it is called
		instead of the application rather than inside it.

		@param path Where to write.
		@return Nought where the file was written.
	**/
	@:native("mdd_requirements_write")
	public static function write(path:cpp.ConstCharStar):Int;

	/**
		Asks a renderer just made what level it reached: the feature level of a Direct3D 11
		device, the version of an OpenGL or OpenGL ES context, or the pixel shader model of a
		Direct3D 9 device. That costs nothing, where asking the driver first costs as much as
		loading it.

		@param renderer The renderer, asked before anything else is made current.
		@return The level as `major << 8 | minor`, `0x0A00` for feature level 10_0 and `0x0200`
			for OpenGL 2.0, or nought where the renderer has no level to read.
	**/
	@:native("mdd_requirements_reached")
	public static function reached(renderer:cpp.Star<Canvas>):Int;
}
