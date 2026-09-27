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
}
