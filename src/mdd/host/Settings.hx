package mdd.host;

import sys.FileSystem;
import sys.io.File;

@:unreflective

/**
	The preferences file: keys and values as text, one to a line.

	It is written whenever a preference changes rather than only at exit, because a
	force quit skips an exit path and the reader loses what they just set.
**/
final class Settings {
	static inline final NAME = "settings.txt";

	/**
		The file beside the program that makes a copy portable.
	**/
	public static inline final MARK = "portable.txt";

	/**
		Where the file is.
	**/
	public var path(default, null):String;

	/**
		Whether this copy keeps its settings beside the program.
	**/
	public var portable(default, null):Bool = false;

	/**
		How many settings the last load found.
	**/
	public var read(default, null):Int = 0;

	final keys:Array<String> = [];
	final said:Array<String> = [];

	/**
		Builds a settings file, working out where it should be where no path is given.

		@param path Where the file is, or an empty string to decide.
	**/
	public function new(path:String = "") {
		if (path != "") {
			this.path = path;
			return;
		}

		portable = carried();
		this.path = Paths.within("settings") + "/" + NAME;
	}

	/**
		@return Whether a portable marker sits beside the program.
	**/
	public static function carried():Bool {
		return Paths.portable();
	}

	/**
		Sets a value and writes the file.

		@param key The setting name.
		@param value What to set it to.
	**/
	public function put(key:String, value:String):Void {
		final at = keys.indexOf(key);

		if (at >= 0) {
			said[at] = value;
			return;
		}

		keys.push(key);
		said.push(value);
	}

	/**
		Sets a whole number.

		@param key The setting name.
		@param value The number.
	**/
	public function whole(key:String, value:Int):Void {
		put(key, Std.string(value));
	}

	/**
		Sets a number.

		@param key The setting name.
		@param value The number.
	**/
	public function number(key:String, value:Float):Void {
		put(key, Std.string(value));
	}

	/**
		Sets a flag.

		@param key The setting name.
		@param value The flag.
	**/
	public function flag(key:String, value:Bool):Void {
		put(key, value ? "true" : "false");
	}

	/**
		@param key The setting name.
		@param fallback What to answer where it is not set.
		@return The value.
	**/
	public function of(key:String, fallback:String = ""):String {
		final at = keys.indexOf(key);
		return at < 0 ? fallback : said[at];
	}

	/**
		@param key The setting name.
		@param fallback What to answer where it is not set.
		@return The value as a whole number.
	**/
	public function asWhole(key:String, fallback:Int = 0):Int {
		final held = Std.parseInt(of(key, ""));
		return held == null ? fallback : held;
	}

	/**
		@param key The setting name.
		@param fallback What to answer where it is not set.
		@return The value as a number.
	**/
	public function asNumber(key:String, fallback:Float = 0):Float {
		final held = Std.parseFloat(of(key, ""));
		return Math.isNaN(held) ? fallback : held;
	}

	/**
		@param key The setting name.
		@param fallback What to answer where it is not set.
		@return The value as a flag.
	**/
	public function asFlag(key:String, fallback:Bool = false):Bool {
		final held = of(key, "");
		if (held == "") return fallback;

		return held == "true" || held == "1" || held == "yes";
	}

	/**
		@return How many settings are held.
	**/
	public inline function count():Int {
		return keys.length;
	}

	/**
		Throws every setting away, in memory only.
	**/
	public function forget():Void {
		keys.resize(0);
		said.resize(0);
		read = 0;

		try {
			if (FileSystem.exists(path)) FileSystem.deleteFile(path);
		} catch (e:Dynamic) {}
	}

	/**
		Reads the file.

		@return False where there was nothing to read.
	**/
	public function load():Bool {
		read = 0;

		if (!FileSystem.exists(path)) return false;

		var text = "";

		try {
			text = File.getContent(path);
		} catch (e:Dynamic) {
			return false;
		}

		for (line in text.split("\n")) {
			final held = StringTools.trim(line);
			if (held == "" || StringTools.startsWith(held, "#")) continue;

			final at = held.indexOf("=");
			if (at <= 0) continue;

			put(StringTools.trim(held.substr(0, at)), StringTools.trim(held.substr(at + 1)));
			read++;
		}

		return true;
	}

	/**
		Writes the file, keys in order so two saves give the same bytes.

		@return False where it could not be written.
	**/
	public function save():Bool {
		final out = new StringBuf();

		for (i in 0...keys.length) {
			out.add(keys[i]);
			out.add(" = ");
			out.add(said[i]);
			out.add("\n");
		}

		try {
			tree(haxe.io.Path.directory(path));
			File.saveContent(path, out.toString());
		} catch (e:Dynamic) {
			return false;
		}

		return true;
	}

	/**
		Makes a folder and every folder above it.

		@param where The folder.
	**/
	static function tree(where:String):Void {
		if (where == "" || FileSystem.exists(where)) return;

		final parent = haxe.io.Path.directory(where);
		if (parent != "" && parent != where) tree(parent);

		FileSystem.createDirectory(where);
	}
}
