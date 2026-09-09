package mdd.host;

@:include("shell.h")

/**
	Registering the project suffix with the desktop, so a double click opens it.

	Everything here is reversible, and `leftovers` is what says whether unregistering
	actually removed everything it wrote.
**/
extern class Shell {
	/**
		@return Nonzero where this platform can register a suffix at all.
	**/
	@:native("mdd_shell_supported")
	public static function supported():Int;

	/**
		@param suffix The file suffix, with no dot.
		@param identity The name this application registers under.
		@return Nonzero where the suffix is registered to this application.
	**/
	@:native("mdd_shell_associated")
	public static function associated(suffix:cpp.ConstCharStar,
		identity:cpp.ConstCharStar):Int;

	/**
		Registers the suffix.

		@param suffix The file suffix, with no dot.
		@param identity The name to register under.
		@param label What the file type is called.
		@param mime Its media type.
		@param name What the application is called.
		@param about A line describing it.
		@return Nonzero where every key was written.
	**/
	@:native("mdd_shell_associate")
	public static function associate(suffix:cpp.ConstCharStar, identity:cpp.ConstCharStar,
		label:cpp.ConstCharStar, mime:cpp.ConstCharStar, name:cpp.ConstCharStar,
		about:cpp.ConstCharStar):Int;

	/**
		Unregisters the suffix, taking back everything `associate` wrote.

		@param suffix The file suffix, with no dot.
		@param identity The name it was registered under.
		@return Nonzero where it was taken back.
	**/
	@:native("mdd_shell_forget")
	public static function forget(suffix:cpp.ConstCharStar,
		identity:cpp.ConstCharStar):Int;

	/**
		@param suffix The file suffix, with no dot.
		@param identity The name it was registered under.
		@return How many keys are still there after unregistering, which should be nought.
	**/
	@:native("mdd_shell_leftovers")
	public static function leftovers(suffix:cpp.ConstCharStar,
		identity:cpp.ConstCharStar):Int;
}
