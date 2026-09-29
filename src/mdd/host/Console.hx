package mdd.host;

@:include("console.h")

/**
	The console a Windows release build is started without.

	A release build on Windows is linked as a windowed program, so starting it from the desktop
	opens no console beside the window. Started from cmd or PowerShell it joins that terminal
	instead, so what it prints is still read there, and `-console` opens one of its own where
	nothing started it from a terminal.
**/
extern class Console {
	/**
		Joins the console of whatever started this, or opens one where asked to and nothing did.
		Does nothing in a build that has a console already, or away from Windows.

		@param open Nonzero to open a console where nothing started this from one.
		@return Nonzero where there is a console now.
	**/
	@:native("mdd_console_attach")
	public static function attach(open:Int):Int;
}
