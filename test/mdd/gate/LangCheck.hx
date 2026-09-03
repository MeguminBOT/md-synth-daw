package mdd.gate;

import mdd.ui.Translation;
import mdd.app.Languages;
import mdd.app.Locale;
import mdd.view.editor.Tracker;

@:unreflective
class LangCheck {
	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  lang");

		final shipped = Languages.shipped();

		if (shipped.length == 0) {
			Sys.println("    nothing was compiled into the binary");
			return 1;
		}

		says("the languages ship", shipped.length >= 1,
			shipped.length + " compiled in: " + shipped.join(", "));

		catalogue();

		for (code in shipped) spoken(code);

		matched(shipped);

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;
		Sys.println("    " + StringTools.rpad(name, " ", 34) + said + (ok ? "" : "   FAILED"));
	}

	static function catalogue():Void {
		final seen:Array<String> = [];
		var twice = "";

		for (key in Locale.ALL) {
			if (seen.indexOf(key) >= 0 && twice == "") twice = key;
			else seen.push(key);
		}

		says("the catalogue is a set", twice == "" && seen.length == Locale.ALL.length,
			twice == "" ? Locale.ALL.length + " keys, each named once"
				: "'" + twice + "' is in the catalogue twice");
	}

	static function spoken(code:String):Void {
		final held = new Translation();
		final taken = Languages.speak(held, code);

		final missing:Array<String> = [];
		for (key in Locale.ALL) if (!held.has(key)) missing.push(key);

		final extra:Array<String> = [];

		for (i in 0...held.count()) {
			final key = held.keyAt(i);
			if (Locale.ALL.indexOf(key) < 0) extra.push(key);
		}

		final said = taken + " strings"
			+ (missing.length == 0 ? "" : ", missing " + shown(missing))
			+ (extra.length == 0 ? "" : ", unused " + shown(extra));

		says(code, taken > 0 && missing.length == 0 && extra.length == 0, said);
	}

	static function matched(shipped:Array<String>):Void {
		final first = new Translation();
		Languages.speak(first, shipped[0]);

		var same = true;
		var apart = "";

		for (at in 1...shipped.length) {
			final held = new Translation();
			Languages.speak(held, shipped[at]);

			if (held.count() != first.count()) {
				same = false;
				apart = shipped[at] + " has " + held.count() + " against " + first.count();
				break;
			}

			for (i in 0...first.count()) {
				if (held.has(first.keyAt(i))) continue;

				same = false;
				apart = shipped[at] + " has no '" + first.keyAt(i) + "'";
				break;
			}

			if (!same) break;
		}

		says("every language has every key", same,
			same ? "all " + shipped.length + " carry the same " + first.count() + " keys"
				: apart);

		final english = new Translation();
		final swedish = new Translation();

		Languages.speak(english, "en-GB");
		Languages.speak(swedish, "sv-SE");

		var translated = 0;

		for (key in Locale.ALL) {
			if (english.of(key) != swedish.of(key)) translated++;
		}

		says("and a language is a language", translated > Std.int(Locale.ALL.length / 2),
			translated + " of " + Locale.ALL.length
			+ " strings differ between en-GB and sv-SE, so it is a translation and not a copy");

		says("a hardware name is never translated",
			english.of(Locale.APP) == swedish.of(Locale.APP)
			&& swedish.of(Locale.VIEW_TRACKER) == "Tracker",
			"the application's name and the hardware words stay as the documentation writes them");
	}

	static function shown(held:Array<String>):String {
		if (held.length <= 4) return held.join(", ");
		return held.slice(0, 4).join(", ") + " and " + (held.length - 4) + " more";
	}
}
