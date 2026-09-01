package mdd.host;

@:include("crash.h")
extern class Crash {
	@:native("mdd_crash_watch")
	public static function watch(path:cpp.ConstCharStar):Void;
}
