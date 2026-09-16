package mdd.app;

import mdd.ui.Translation;

/**
	Which languages ship, what they are called, and which one to start in.
**/
class Languages {
	/**
		@return The language codes that ship, in order.
	**/
	public static function shipped():Array<String> {
		final held = mdd.Config.SPOKEN;
		return held == "" ? [] : held.split(",");
	}

	/**
		@param code A language code.
		@return What that language is called, in itself rather than in English.
	**/
	public static function named(code:String):String {
		return switch (code) {
			case "en-GB": "English (United Kingdom)";
			case "en-US": "English (United States)";
			case "sv-SE": "Svenska";
			case "de-DE": "Deutsch";
			case "es-ES": "Español";
			case "fr-FR": "Français";
			case "pl-PL": "Polski";
			case "pt-BR": "Português (Brasil)";
			case "pt-PT": "Português (Portugal)";
			case "ru-RU": "Русский";
			case "ja-JP": "日本語";
			case "zh-CN": "简体中文";
			case "ko-KR": "한국어";
			case _: code;
		}
	}

	/**
		@param code A language code.
		@return The string naming it in whichever language is in force, or -1 where there is
			none. Only a language needing a face of its own has one: its own name is written
			in that face, so it cannot be drawn until the face is here, and the list has to
			call it something that can.
	**/
	public static function called(code:String):Int {
		return switch (code) {
			case "ja-JP": Locale.LANGUAGE_NAME_JA_JP;
			case "zh-CN": Locale.LANGUAGE_NAME_ZH_CN;
			case "ko-KR": Locale.LANGUAGE_NAME_KO_KR;
			case _: -1;
		}
	}

	/**
		Loads a language into a table, falling back to the first for any key it does not
		carry.

		@param held The table to load into.
		@param code Which language.
		@return How many strings it carried.
	**/
	public static function speak(held:Translation, code:String):Int {
		final bytes = haxe.Resource.getBytes("lang." + code);
		if (bytes == null) return 0;

		final taken = held.take(bytes);
		if (taken > 0) held.speak(code);

		return taken;
	}

	/**
		@return The language everything falls back to, which is the one the catalogue is
			generated from. It is named rather than taken from the front of the list,
			because the list is in alphabetical order and a language added ahead of it
			would otherwise become what every missing string falls back to.
	**/
	public static function first():String {
		final held = shipped();
		if (held.length == 0) return "en-GB";

		for (code in held) if (code == "en-GB") return code;

		return held[0];
	}

	/**
		@param code A language code.
		@return Whether it ships.
	**/
	public static function known(code:String):Bool {
		return shipped().indexOf(code) >= 0;
	}

	/**
		@return Which language to start in, from what the account is set to, or the fallback where
			that is not one that ships.
	**/
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
