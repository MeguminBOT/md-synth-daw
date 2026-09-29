package mdd.host;

@:include("disk.h")

/**
	What the operating system does with files that the standard library cannot: putting one in
	place of another in a single step.

	`sys.FileSystem.rename` refuses a name that is taken on Windows, so a save had to delete the old
	file and then rename the new one, and anything that stopped between the two left the name with
	neither. `Paths.replaces` and `Paths.saves` are what the rest of the application calls.
**/
extern class Disk {
	/**
		@param from The file just written.
		@param onto The name it takes. Whatever was there is replaced.
		@return Nonzero where it was moved.
	**/
	@:native("mdd_disk_replace")
	public static function replace(from:cpp.ConstCharStar, onto:cpp.ConstCharStar):Int;
}
