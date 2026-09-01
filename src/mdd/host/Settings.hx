package mdd.host;

import sys.FileSystem;
import sys.io.File;

@:unreflective
final class Settings {
	public static inline final NAME = "settings.txt";
	public static inline final MARK = "portable.txt";

	public var path(default, null):String;
	public var portable(default, null):Bool = false;
	public var read(default, null):Int = 0;

	final keys:Array<String> = [];
	final said:Array<String> = [];

	public function new(path:String = "") {
		if (path != "") {
			this.path = path;
			return;
		}

		portable = carried();
		this.path = (portable ? Paths.beside() : Paths.settings()) + "/" + NAME;
	}

	public static function carried():Bool {
		final beside = Paths.beside();
		return FileSystem.exists(beside + "/" + MARK) || FileSystem.exists(beside + "/" + NAME);
	}

	public function put(key:String, value:String):Void {
		final at = keys.indexOf(key);

		if (at >= 0) {
			said[at] = value;
			return;
		}

		keys.push(key);
		said.push(value);
	}

	public function whole(key:String, value:Int):Void {
		put(key, Std.string(value));
	}

	public function number(key:String, value:Float):Void {
		put(key, Std.string(value));
	}

	public function flag(key:String, value:Bool):Void {
		put(key, value ? "true" : "false");
	}

	public function of(key:String, fallback:String = ""):String {
		final at = keys.indexOf(key);
		return at < 0 ? fallback : said[at];
	}

	public function asWhole(key:String, fallback:Int = 0):Int {
		final held = Std.parseInt(of(key, ""));
		return held == null ? fallback : held;
	}

	public function asNumber(key:String, fallback:Float = 0):Float {
		final held = Std.parseFloat(of(key, ""));
		return Math.isNaN(held) ? fallback : held;
	}

	public function asFlag(key:String, fallback:Bool = false):Bool {
		final held = of(key, "");
		if (held == "") return fallback;

		return held == "true" || held == "1" || held == "yes";
	}

	public inline function count():Int {
		return keys.length;
	}

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

	static function tree(where:String):Void {
		if (where == "" || FileSystem.exists(where)) return;

		final parent = haxe.io.Path.directory(where);
		if (parent != "" && parent != where) tree(parent);

		FileSystem.createDirectory(where);
	}
}
