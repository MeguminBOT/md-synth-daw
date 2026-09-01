package mdd.host;

import sys.FileSystem;

class Paths {
	public static function settings():String {
		#if windows
		return beneath(env("APPDATA"), "mdd");
		#elseif mac
		return beneath(home() + "/Library/Application Support", "mdd");
		#else
		final given = env("XDG_CONFIG_HOME");
		return beneath(given != "" ? given : home() + "/.config", "mdd");
		#end
	}

	public static function data():String {
		#if windows
		return beneath(env("LOCALAPPDATA"), "mdd");
		#elseif mac
		return beneath(home() + "/Library/Application Support", "mdd");
		#else
		final given = env("XDG_DATA_HOME");
		return beneath(given != "" ? given : home() + "/.local/share", "mdd");
		#end
	}

	public static function documents():String {
		#if windows
		return beneath(home() + "/Documents", "mdd");
		#elseif mac
		return beneath(home() + "/Documents", "mdd");
		#else
		return beneath(home(), "mdd");
		#end
	}

	public static function beside():String {
		final exe = Sys.programPath();
		return exe == "" ? Sys.getCwd() : haxe.io.Path.directory(exe);
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
