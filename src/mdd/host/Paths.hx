package mdd.host;

import sys.FileSystem;

/**
	Where everything lives on each platform, and the one place a platform gate about a
	path belongs.

	Haxe does not define `windows`, `linux` or `mac` for the C++ target, so every gate
	here depends on the build passing the platform define. Without it the settings
	directory silently resolved to the Linux path on Windows, with nothing warning.
**/
class Paths {
	/**
		@return Where preferences are kept, made if it does not exist.
	**/
	public static function settings():String {
		#if windows
		return beneath(env("APPDATA"), mdd.Config.SHORT);
		#elseif mac
		return beneath(home() + "/Library/Application Support", mdd.Config.SHORT);
		#else
		final given = env("XDG_CONFIG_HOME");
		return beneath(given != "" ? given : home() + "/.config", mdd.Config.SHORT);
		#end
	}

	/**
		@return Where larger files that are not the reader's own are kept.
	**/
	public static function data():String {
		#if windows
		return beneath(env("LOCALAPPDATA"), mdd.Config.SHORT);
		#elseif mac
		return beneath(home() + "/Library/Application Support", mdd.Config.SHORT);
		#else
		final given = env("XDG_DATA_HOME");
		return beneath(given != "" ? given : home() + "/.local/share", mdd.Config.SHORT);
		#end
	}

	/**
		@return The account documents folder.
	**/
	public static function documents():String {
		#if windows
		return home() + "/Documents";
		#elseif mac
		return home() + "/Documents";
		#else
		final given = env("XDG_DOCUMENTS_DIR");
		return given != "" ? given : home() + "/Documents";
		#end
	}

	static inline final USERDATA = "userdata";

	/**
		@return This platform as it appears in a package name: windows, mac or linux.
	**/
	public static function platform():String {
		#if windows
		return "windows";
		#elseif mac
		return "mac";
		#else
		return "linux";
		#end
	}

	/**
		@return This architecture as it appears in a package name: x86_64 or arm64.
	**/
	public static function machine():String {
		#if HXCPP_ARM64
		return "arm64";
		#else
		return "x86_64";
		#end
	}


	/**
		@return Whether this copy keeps its settings beside the program rather than in the account.
			A marker file or a userdata folder beside the executable says so.
	**/
	public static function portable():Bool {
		final held = beside() + "/" + USERDATA;

		final marked = sys.FileSystem.exists(beside() + "/portable.txt")
			|| sys.FileSystem.exists(held);

		return marked && usable(held);
	}

	/**
		@param where A directory this would keep things in.
		@return Whether it is there, or can be made.

		The marker on its own is not enough to go by. An installer carried one into
		Program Files, where nothing is written without being asked for, so a copy that
		took the marker at its word put its settings where they could not go: every run
		started as though it were the first, asking again which language to use and
		remembering nothing that was chosen. A place that will not even be made is not a
		place to keep anything.
	**/
	static function usable(where:String):Bool {
		make(where);
		return sys.FileSystem.exists(where);
	}

	/**
		The environment variable that puts the userdata folder somewhere else entirely, ahead of
		portable mode and the documents folder. The gate sets it, so nothing it saves, backs up or
		logs reaches the account's own userdata folder.
	**/
	public static inline final USERDATA_VARIABLE = "MDD_USERDATA";

	/**
		@return Where this copy keeps everything the reader owns: the folder `USERDATA_VARIABLE`
			names where it is set, and otherwise beside the program or in the documents folder,
			depending on whether this copy is portable.
	**/
	public static function userdata():String {
		final given = env(USERDATA_VARIABLE);
		if (given != "") return tidy(given);

		if (portable()) return beside() + "/" + USERDATA;
		return documents() + "/" + mdd.Config.TITLE;
	}

	/**
		Finds a folder under the userdata folder, making it if it is not there.

		@param what The folder name.
		@return Its full path.
	**/
	public static function within(what:String):String {
		final where = userdata() + "/" + what;
		make(where);
		return where;
	}

	/**
		Makes a folder and every folder above it.

		@param where The folder.
	**/
	public static function make(where:String):Void {
		if (where == "" || sys.FileSystem.exists(where)) return;

		final parent = haxe.io.Path.directory(where);
		if (parent != "" && parent != where) make(parent);

		try {
			sys.FileSystem.createDirectory(where);
		} catch (e:Dynamic) {}
	}

	/**
		Opens a folder in the desktop's file manager, making it first where it is missing.

		@param where The folder.
		@return Whether the desktop took it.
	**/
	public static function reveal(where:String):Bool {
		make(where);
		if (!FileSystem.exists(where)) return false;

		#if windows
		final said = StringTools.replace(FileSystem.fullPath(where), "/", "\\");
		#else
		final said = "file://" + escaped(FileSystem.fullPath(where));
		#end

		return Sdl.openUrl(said) != 0;
	}

	/**
		Opens an address in the desktop's web browser.

		@param address The address, whole.
		@return Whether the desktop took it.
	**/
	public static function browse(address:String):Bool {
		return address != "" && Sdl.openUrl(address) != 0;
	}

	/**
		@param path A path.
		@return It with every byte a URL cannot carry as it stands written as a percent
			escape.
	**/
	static function escaped(path:String):String {
		final bytes = haxe.io.Bytes.ofString(path);
		final out = new StringBuf();

		for (at in 0...bytes.length) {
			final code = bytes.get(at);

			final letter = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
			final digit = code >= 48 && code <= 57;
			final mark = code == 45 || code == 46 || code == 95 || code == 126 || code == 47;

			if (letter || digit || mark) {
				out.addChar(code);
			} else {
				out.add("%");
				out.add(StringTools.hex(code, 2));
			}
		}

		return out.toString();
	}

	/**
		Removes a file, or a folder and everything under it.

		@param where What to remove. Nothing happens where it does not exist.
	**/
	public static function clear(where:String):Void {
		if (where == "" || !FileSystem.exists(where)) return;

		if (!FileSystem.isDirectory(where)) {
			try {
				FileSystem.deleteFile(where);
			} catch (e:Dynamic) {}

			return;
		}

		for (entry in FileSystem.readDirectory(where)) clear(where + "/" + entry);

		try {
			FileSystem.deleteDirectory(where);
		} catch (e:Dynamic) {}
	}

	/**
		@return The folder the running program sits in.
	**/
	public static function beside():String {
		final exe = Sys.programPath();
		final held = exe == "" ? Sys.getCwd() : haxe.io.Path.directory(exe);

		return haxe.io.Path.removeTrailingSlashes(StringTools.replace(held, "\\", "/"));
	}

	/**
		@return What an executable is called on this platform, which is `.exe` on Windows and
			nothing elsewhere.
	**/
	public static inline function suffix():String {
		#if windows
		return ".exe";
		#else
		return "";
		#end
	}

	/**
		@return The account home folder.
	**/
	public static function home():String {
		#if windows
		final drive = env("HOMEDRIVE");
		final path = env("HOMEPATH");
		if (drive != "" && path != "") return tidy(drive + path);
		final profile = env("USERPROFILE");
		if (profile != "") return tidy(profile);
		#end

		final given = env("HOME");
		return given != "" ? tidy(given) : Sys.getCwd();
	}

	/**
		@param name An environment variable.
		@return Its value, or an empty string where it is not set.
	**/
	static function env(name:String):String {
		final given = Sys.getEnv(name);
		return given == null ? "" : given;
	}

	/**
		@param path A path.
		@return It with forward slashes and no trailing one.
	**/
	static inline function tidy(path:String):String {
		return haxe.io.Path.removeTrailingSlashes(StringTools.replace(path, "\\", "/"));
	}

	/**
		Finds a folder inside another, making it if it is not there.

		@param parent The folder to look in.
		@param leaf The folder wanted.
		@return Its full path.
	**/
	static function beneath(parent:String, leaf:String):String {
		final path = tidy(parent) + "/" + leaf;
		if (!FileSystem.exists(path)) {
			try {
				FileSystem.createDirectory(path);
			} catch (e:Dynamic) {}
		}
		return path;
	}
}
