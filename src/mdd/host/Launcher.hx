package mdd.host;

@:include("launcher.h")

/**
	Starting a program that outlives this one.

	What `Sys.command` starts on Windows inherits every handle this process has open, and
	`start` passes them on again, so a file this process holds stays open for as long as what it
	started runs. That is what the update handover cannot have: it waits for a file this process
	holds to become deletable, and a handover holding that file itself waits forever.
**/
extern class Launcher {
	/**
		Starts a command line with no window and none of this process's handles, and returns at
		once. Windows only.

		@param command The whole command line, as CreateProcess reads one.
		@return Nonzero where it was started. Nought elsewhere than Windows, where nothing needs
			it.
	**/
	@:native("mdd_launcher_detached")
	public static function detached(command:cpp.ConstCharStar):Int;
}
