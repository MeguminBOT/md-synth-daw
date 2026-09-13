package mdd.gate;

import sys.FileSystem;

@:unreflective

/**
	What the binary needs beside it, and whether it is there.

	Windows links the vendored SDL3 and the build ships the DLL. macOS and Linux link
	whatever the package manager installed, so the binary comes out naming an absolute
	path: `/opt/homebrew` on an arm64 Mac, `/usr/local` on an Intel one, and the
	distribution's own directory on Linux. Nothing at that path exists on the machine an
	archive is unpacked on, and the loader stops rather than looking elsewhere, so a
	release built that way cannot start at all.

	The binary read is this one, because the gate is shipped into `export/bin` by the same
	step the application is and carries whatever the application carries. The application
	is read too where it has been built.
**/
class CarryCheck {
	static inline final LIBRARY = "SDL3";

	static var failed:Int = 0;
	static var ran:Int = 0;

	/**
		@param args The gate's arguments, unused.
		@return Nought where every binary finds its library beside itself.
	**/
	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  carry");

		final held = Sys.programPath();
		final beside = haxe.io.Path.directory(held);

		looked(held, "the gate");

		final suffix = Sys.systemName() == "Windows" ? ".exe" : "";
		final app = beside + "/mdd" + suffix;

		if (FileSystem.exists(app) && app != held) looked(app, "the application");

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	/**
		Reads what one binary links and says whether the library sits beside it.

		@param exe The binary.
		@param said What to call it.
	**/
	static function looked(exe:String, said:String):Void {
		final beside = haxe.io.Path.directory(exe);
		final names = FileSystem.exists(beside) ? FileSystem.readDirectory(beside) : [];

		var found = "";
		for (name in names) {
			if (name.indexOf(LIBRARY) >= 0 && !FileSystem.isDirectory(beside + "/" + name)) {
				found = name;
			}
		}

		says(said + " carries " + LIBRARY + " beside it", found != "",
			found == "" ? "nothing in " + beside + " is named for " + LIBRARY
				+ ", so an archive of it would not start anywhere the library is missing"
				: found + " sits beside it");

		final wanted = wants(exe);

		if (wanted == "") {
			says("and " + said + " names no path outside its own folder", true,
				"nothing outside the operating system is named by an absolute path");
			return;
		}

		says("and " + said + " names no path outside its own folder", false,
			"it loads " + wanted + ", which is where this machine keeps the library rather"
			+ " than where the archive puts it");
	}

	/**
		@param exe A binary.
		@return The absolute path it loads the library from, or an empty string where it
			loads it from beside itself or the tools that would say are missing.
	**/
	static function wants(exe:String):String {
		final mac = Sys.systemName() == "Mac";
		if (Sys.systemName() == "Windows") return "";

		final said = reads(mac ? "otool" : "ldd", mac ? ["-L", exe] : [exe]);
		if (said == "") return "";

		final beside = folded(haxe.io.Path.directory(FileSystem.absolutePath(exe)));

		for (line in said.split("\n")) {
			final held = StringTools.trim(line);

			if (StringTools.endsWith(held, ":")) continue;
			if (held.indexOf(LIBRARY) < 0) continue;

			final from = mac ? held.split(" ")[0]
				: (held.indexOf("=> ") < 0 ? ""
					: StringTools.trim(held.split("=> ")[1]).split(" ")[0]);

			if (from == "" || StringTools.startsWith(from, "@")) continue;
			if (!FileSystem.exists(from)) continue;
			if (folded(haxe.io.Path.directory(from)) == beside) continue;

			return from;
		}

		return "";
	}

	/**
		@param where A directory.
		@return It as one absolute spelling, so two paths reaching the same folder compare
			equal however the loader wrote them.
	**/
	static function folded(where:String):String {
		if (where == "") return "";

		try {
			return haxe.io.Path.removeTrailingSlashes(
				StringTools.replace(FileSystem.absolutePath(where), "\\", "/"));
		} catch (e:Dynamic) {
			return where;
		}
	}

	/**
		@param name A program.
		@param args What to pass it.
		@return What it wrote, or an empty string where it would not run.
	**/
	static function reads(name:String, args:Array<String>):String {
		try {
			final run = new sys.io.Process(name, args);
			final said = run.stdout.readAll().toString();
			final code = run.exitCode();

			run.close();
			return code == 0 ? said : "";
		} catch (e:Dynamic) {
			return "";
		}
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 34) + said
			+ (ok ? "" : "   FAILED"));
	}
}
