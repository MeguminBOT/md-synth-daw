package mdd.host;

/**
	Running another program and waiting for it to finish, with no window.

	`Sys.command` runs a command through the system shell, which on Windows is `cmd.exe`, a console
	program. A release build is a windowed program with no console to lend it, so every command it
	ran opened a console window of its own for as long as the command took. A program run here gets
	no window on any platform.
**/
class Command {
	/**
		Runs a program and waits for it. Whatever it prints is read and thrown away. Blocks the
		calling thread for as long as the program runs, without holding up the collector, so it
		belongs on a thread of its own wherever the program could take a while.

		@param program The program, found on the path.
		@param args Its arguments, each passed as one.
		@return What it exited with, or -1 where it would not start.
	**/
	public static function runs(program:String, args:Array<String>):Int {
		try {
			final process = new sys.io.Process(program, args);

			process.stdin.close();
			process.stdout.readAll();
			process.stderr.readAll();

			final code = process.exitCode();
			process.close();

			return code;
		} catch (e:haxe.Exception) {
			return -1;
		}
	}
}
