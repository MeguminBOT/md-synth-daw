package mdd.host;

import sys.FileSystem;

class Paths {
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

	public static function platform():String {
		#if windows
		return "windows";
		#elseif mac
		return "mac";
		#else
		return "linux";
		#end
	}


	public static function portable():Bool {
		return sys.FileSystem.exists(beside() + "/portable.txt")
			|| sys.FileSystem.exists(beside() + "/" + USERDATA);
	}

	public static function userdata():String {
		if (portable()) return beside() + "/" + USERDATA;
		return documents() + "/" + mdd.Config.TITLE;
	}

	public static function within(what:String):String {
		final where = userdata() + "/" + what;
		make(where);
		return where;
	}

	public static function make(where:String):Void {
		if (where == "" || sys.FileSystem.exists(where)) return;

		final parent = haxe.io.Path.directory(where);
		if (parent != "" && parent != where) make(parent);

		try {
			sys.FileSystem.createDirectory(where);
		} catch (e:Dynamic) {}
	}

	public static function beside():String {
		final exe = Sys.programPath();
		final held = exe == "" ? Sys.getCwd() : haxe.io.Path.directory(exe);

		return haxe.io.Path.removeTrailingSlashes(StringTools.replace(held, "\\", "/"));
	}

	public static inline function suffix():String {
		#if windows
		return ".exe";
		#else
		return "";
		#end
	}

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

	static function env(name:String):String {
		final given = Sys.getEnv(name);
		return given == null ? "" : given;
	}

	static inline function tidy(path:String):String {
		return haxe.io.Path.removeTrailingSlashes(StringTools.replace(path, "\\", "/"));
	}

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
