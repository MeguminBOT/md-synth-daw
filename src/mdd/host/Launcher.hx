package mdd.host;

@:include("launcher.h")

/**
	Starting a program that outlives this one, as this account or as an administrator.

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

	/**
		Starts a program as an administrator, which Windows asks to be allowed first. Blocks until
		that is answered, and should be called while this application's window is still in front:
		asked from the background, the question only flashes on the taskbar. Windows only.

		@param program The program, found the way the shell finds one.
		@param parameters The rest of its command line.
		@return 1 where it was started, 0 where the question was declined, and -1 where it could
			not be asked, which is every answer away from Windows.
	**/
	@:native("mdd_launcher_elevated")
	public static function elevated(program:cpp.ConstCharStar, parameters:cpp.ConstCharStar):Int;

	/**
		@return This process's own identifier, which a handover away from Windows waits on to see
			this process close.
	**/
	@:native("mdd_launcher_process")
	public static function process():Int;
}
