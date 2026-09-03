package mdd.app;

import mdd.ui.Translation;

class Languages {
	public static function shipped():Array<String> {
		final held = mdd.Config.SPOKEN;
		return held == "" ? [] : held.split(",");
	}

	public static function named(code:String):String {
		return switch (code) {
			case "en-GB": "English (United Kingdom)";
			case "en-US": "English (United States)";
			case "sv-SE": "Svenska";
			case _: code;
		}
	}

	public static function speak(held:Translation, code:String):Int {
		final bytes = haxe.Resource.getBytes("lang." + code);
		if (bytes == null) return 0;

		final taken = held.take(bytes);
		if (taken > 0) held.speak(code);

		return taken;
	}

	public static function first():String {
		final held = shipped();
		return held.length == 0 ? "en-GB" : held[0];
	}

	public static function known(code:String):Bool {
		return shipped().indexOf(code) >= 0;
	}

	public static function guessed():String {
		final held = shipped();
		if (held.length == 0) return "en-GB";

		final asked = wanted();
		if (asked == "") return first();

		for (code in held) if (code == asked) return code;

		final part = asked.split("-")[0];
		for (code in held) if (code.split("-")[0] == part) return code;

		return first();
	}

	static function wanted():String {
		for (name in ["LANG", "LANGUAGE", "LC_ALL"]) {
			final held = Sys.getEnv(name);
			if (held == null || held == "") continue;

			return StringTools.replace(held.split(".")[0], "_", "-");
		}

		return "";
	}
}
