package mdd.host;

@:include("dialog.h")
extern class Dialog {
	public static inline final WAITING = 0;
	public static inline final CHOSEN = 1;
	public static inline final CANCELLED = 2;
	public static inline final FAILED = 3;

	@:native("mdd_dialog_open")
	public static function open(window:cpp.Star<Window>, label:cpp.ConstCharStar,
		suffix:cpp.ConstCharStar, where:cpp.ConstCharStar):cpp.Star<Chooser>;

	@:native("mdd_dialog_save")
	public static function save(window:cpp.Star<Window>, label:cpp.ConstCharStar,
		suffix:cpp.ConstCharStar, where:cpp.ConstCharStar):cpp.Star<Chooser>;

	@:native("mdd_dialog_state")
	public static function state(dialog:cpp.Star<Chooser>):Int;

	@:native("mdd_dialog_path")
	public static function path(dialog:cpp.Star<Chooser>):cpp.ConstCharStar;

	@:native("mdd_dialog_close")
	public static function close(dialog:cpp.Star<Chooser>):Void;
}
