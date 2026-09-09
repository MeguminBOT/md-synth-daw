package mdd.host;

@:include("crash.h")

/**
	The crash handler: what turns a fault into a report naming the Haxe line.

	A release build keeps no Haxe stack, because the line markers hxcpp writes expand
	to nothing without the debug defines. The text is still in the generated C++, and
	the symbols carry the generated file and line for every address, so reading the
	generated file at the line the symbols name gives the Haxe line for nothing at run
	time.
**/
extern class Crash {
	/**
		Installs the handler.

		@param path Where a report is written.
		@param label What to call the process in it.
		@param announce Whether to tell the reader a report was written.
	**/
	@:native("mdd_crash_watch")
	public static function watch(path:cpp.ConstCharStar, label:cpp.ConstCharStar,
		announce:Bool):Void;

	/**
		Names the calling thread in any report, and reserves the last of its stack for
		the handler. A stack overflow leaves no room to report a stack overflow, so
		every thread that could overflow has to call this, not just the first one.

		@param name What to call this thread.
	**/
	@:native("mdd_crash_thread")
	public static function thread(name:cpp.ConstCharStar):Void;
}
