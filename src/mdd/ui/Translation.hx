package mdd.ui;

@:unreflective

/**
	The table every string the interface shows comes from.

	A string is looked up by a number rather than by name, so a lookup is an array
	index and not a search. Hardware and format names are deliberately not in the
	table: `FM3`, `$4C`, `TL` and `bpm` stay as the documentation writes them in every
	language.
**/
final class Translation {
	/**
		Which language is loaded.
	**/
	public var language(default, null):String = "en";

	/**
		How many keys the loaded language did not carry, and so fell back for.
	**/
	public var missing(default, null):Int = 0;

	final keys:Array<String> = [];
	final said:Array<String> = [];

	/**
		Builds an empty table.
	**/
	public function new() {}

	/**
		Sets one string.

		@param key The key.
		@param saying What it says.
	**/
	public function put(key:String, saying:String):Void {
		final at = keys.indexOf(key);

		if (at >= 0) {
			said[at] = saying;
			return;
		}

		keys.push(key);
		said.push(saying);
	}

	/**
		@param id A string key, as a number.
		@return What it says, or the key name where the language does not carry it.
	**/
	public function of(id:Int):String {
		if (id >= 0 && id < said.length) return said[id];

		missing++;
		return "";
	}

	/**
		Puts values into the numbered places a line leaves for them.

		A line names its values by number rather than by where they fall in the
		sentence, because word order is the first thing a language changes: what
		comes last in one comes first in another, and a line built by joining
		pieces can only ever be right in the language it was written in.

		@param pattern What the table holds, with `{0}` where the first value goes.
		@param values What to put in those places, in order.
		@return The line with every place filled. A place with no value behind it is
			left as it stands, so a mistranslated line is readable rather than blank.
	**/
	public static function filled(pattern:String, values:Array<String>):String {
		if (values.length == 0 || pattern.indexOf("{") < 0) return pattern;

		final out = new StringBuf();
		var at = 0;

		while (at < pattern.length) {
			final open = pattern.indexOf("{", at);
			final shut = open < 0 ? -1 : pattern.indexOf("}", open);

			if (open < 0 || shut < 0) {
				out.addSub(pattern, at, pattern.length - at);
				break;
			}

			out.addSub(pattern, at, open - at);

			final which = Std.parseInt(pattern.substring(open + 1, shut));

			if (which == null || which < 0 || which >= values.length) {
				out.addSub(pattern, open, shut - open + 1);
			} else out.add(values[which]);

			at = shut + 1;
		}

		return out.toString();
	}

	/**
		@param key A string key, by name.
		@return What it says.
	**/
	public function named(key:String):String {
		final at = keys.indexOf(key);
		return at < 0 ? key : said[at];
	}

	/**
		@param key A string key, by name.
		@return Whether the table carries it.
	**/
	public function has(key:String):Bool {
		return keys.indexOf(key) >= 0;
	}

	/**
		@return How many strings are held.
	**/
	public inline function count():Int {
		return keys.length;
	}

	/**
		@param index A position in the table.
		@return The key there.
	**/
	public function keyAt(index:Int):String {
		return index < 0 || index >= keys.length ? "" : keys[index];
	}

	/**
		Throws every string away.
	**/
	public function forget():Void {
		missing = 0;
	}

	/**
		Records which language is loaded. It does not load one.

		@param language The language code.
	**/
	public function speak(language:String):Void {
		this.language = language;
	}

	/**
		Reads a language file.

		@param bytes The file.
		@return How many strings it carried.
	**/
	public function take(bytes:haxe.io.Bytes):Int {
		if (bytes == null || bytes.length < 8 || bytes.getString(0, 4) != "MDL1") return 0;

		final input = new haxe.io.BytesInput(bytes);
		input.position = 4;

		final many = input.readInt32();
		var taken = 0;

		for (i in 0...many) {
			if (input.position + 2 > bytes.length) break;

			final keyLength = input.readUInt16();
			if (input.position + keyLength + 2 > bytes.length) break;

			final key = input.readString(keyLength);
			final saidLength = input.readUInt16();

			if (input.position + saidLength > bytes.length) break;

			put(key, input.readString(saidLength));
			taken++;
		}

		return taken;
	}

	/**
		Reads a language document, ignoring blank lines and lines that begin with a
		hash.

		@param text The document.
		@return How many strings it carried.
	**/
	public function read(text:String):Int {
		var taken = 0;

		for (line in text.split("\n")) {
			final held = StringTools.trim(line);
			if (held == "" || StringTools.startsWith(held, "#")) continue;

			final at = held.indexOf("=");
			if (at <= 0) continue;

			put(StringTools.trim(held.substr(0, at)), StringTools.trim(held.substr(at + 1)));
			taken++;
		}

		return taken;
	}

	/**
		@return The whole table as a document, keys in order.
	**/
	public function write():String {
		final out = new StringBuf();

		for (i in 0...keys.length) {
			out.add(keys[i]);
			out.add(" = ");
			out.add(said[i]);
			out.add("\n");
		}

		return out.toString();
	}
}
