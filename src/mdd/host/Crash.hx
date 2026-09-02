package mdd.host;

@:include("crash.h")
extern class Crash {
	@:native("mdd_crash_watch")
	public static function watch(path:cpp.ConstCharStar, label:cpp.ConstCharStar,
		announce:Bool):Void;

	@:native("mdd_crash_thread")
	public static function thread(name:cpp.ConstCharStar):Void;
}
