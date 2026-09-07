package mdd.host;

@:include("shell.h")
extern class Shell {
	@:native("mdd_shell_supported")
	public static function supported():Int;

	@:native("mdd_shell_associated")
	public static function associated(suffix:cpp.ConstCharStar,
		identity:cpp.ConstCharStar):Int;

	@:native("mdd_shell_associate")
	public static function associate(suffix:cpp.ConstCharStar, identity:cpp.ConstCharStar,
		label:cpp.ConstCharStar, mime:cpp.ConstCharStar, name:cpp.ConstCharStar,
		about:cpp.ConstCharStar):Int;

	@:native("mdd_shell_forget")
	public static function forget(suffix:cpp.ConstCharStar,
		identity:cpp.ConstCharStar):Int;

	@:native("mdd_shell_leftovers")
	public static function leftovers(suffix:cpp.ConstCharStar,
		identity:cpp.ConstCharStar):Int;
}
