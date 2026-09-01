package mdd.ui;

@:unreflective
final class Words {
	public var language(default, null):String = "en";
	public var missing(default, null):Int = 0;

	final keys:Array<String> = [];
	final said:Array<String> = [];

	public function new() {}

	public function put(key:String, saying:String):Void {
		final at = keys.indexOf(key);

		if (at >= 0) {
			said[at] = saying;
			return;
		}

		keys.push(key);
		said.push(saying);
	}

	public function of(key:String):String {
		final at = keys.indexOf(key);
		if (at >= 0) return said[at];

		missing++;
		return key;
	}

	public function has(key:String):Bool {
		return keys.indexOf(key) >= 0;
	}

	public inline function count():Int {
		return keys.length;
	}

	public function keyAt(index:Int):String {
		return index < 0 || index >= keys.length ? "" : keys[index];
	}

	public function forget():Void {
		missing = 0;
	}

	public function speak(language:String):Void {
		this.language = language;
	}

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
