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
		drawable(shipped, args.length > 0 ? args[0] : Gate.root);
		scripted(args.length > 0 ? args[0] : Gate.root);

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
		Sys.println("    " + StringTools.rpad(name, " ", 44) + said + (ok ? "" : "   FAILED"));
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

	static function chain(root:String):Array<Int> {
		final held:Array<Int> = [];
		final where = root + "/vendor/fonts/";

		for (name in ["Go-Regular.ttf"].concat(mdd.Typeface.FALLBACK)) {
			if (!sys.FileSystem.exists(where + name)) continue;

			final face = mdd.host.Text.load(where + name);
			if (face >= 0) held.push(face);
		}

		return held;
	}

	static function covers(faces:Array<Int>, code:Int, wide:cpp.RawPointer<Int>,
			tall:cpp.RawPointer<Int>):Bool {
		for (face in faces) {
			if (mdd.host.Text.extent(face, 15, code, wide, tall) != 0) return true;
		}

		return false;
	}

	static function scripted(root:String):Void {
		final faces = chain(root);

		if (faces.length == 0) {
			says("every script the fonts promise can be drawn", false, "no faces to ask");
			return;
		}

		final asked = new haxe.ds.Vector<Int>(2);
		final wide = cpp.Pointer.arrayElem(asked.toData(), 0).raw;
		final tall = cpp.Pointer.arrayElem(asked.toData(), 1).raw;

		final samples = [
			"english", "The quick brown fox",
			"swedish", "Blå ängar på Öland",
			"german", "Größenwahn für Öl",
			"french", "Où être, ça y est",
			"vietnamese", "Tiếng Việt rất đẹp",
			"greek", "Ρυθμίσεις ήχου",
			"cyrillic", "Настройки звука",
			"japanese", "ドラム パターンを編集",
			"chinese", "编辑鼓组模式",
			"korean", "드럼 패턴 편집"
		];

		final lost:Array<String> = [];
		var counted = 0;

		var index = 0;
		while (index < samples.length) {
			final name = samples[index];
			final said = samples[index + 1];

			index += 2;

			var at = 0;
			while (at < said.length) {
				final one = mdd.ui.Font.codeAt(said, at);
				at += mdd.ui.Font.step(one);

				counted++;
				if (covers(faces, one, wide, tall)) continue;

				lost.push(name + " U+" + StringTools.hex(one, 4));
			}
		}

		for (face in faces) mdd.host.Text.free(face);

		says("every script the fonts promise can be drawn", lost.length == 0,
			lost.length == 0
				? counted + " characters over " + Std.int(samples.length / 2)
					+ " scripts, all cut from the chain of " + faces.length + " faces"
				: lost.length + " with no glyph anywhere: " + lost.slice(0, 5).join(", "));
	}

	static function drawable(shipped:Array<String>, root:String):Void {
		final where = root + "/vendor/fonts/Go-Regular.ttf";
		final face = mdd.host.Text.load(where);

		if (face < 0) {
			says("every letter a language ships can be drawn", false, "no face at " + where);
			return;
		}

		final asked = new haxe.ds.Vector<Int>(2);
		final wide = cpp.Pointer.arrayElem(asked.toData(), 0).raw;
		final tall = cpp.Pointer.arrayElem(asked.toData(), 1).raw;

		final lost:Array<String> = [];

		var counted = 0;
		var widest = 0;

		for (code in shipped) {
			final held = new Translation();
			Languages.speak(held, code);

			for (index in 0...held.count()) {
				final key = held.keyAt(index);
				final said = held.of(key);

				var at = 0;

				while (at < said.length) {
					final one = mdd.ui.Font.codeAt(said, at);
					at += mdd.ui.Font.step(one);

					counted++;
					if (one > widest) widest = one;

					if (mdd.host.Text.extent(face, 15, one, wide, tall) != 0) continue;

					final shown = code + " " + key + " U+" + StringTools.hex(one, 4);
					if (lost.indexOf(shown) < 0) lost.push(shown);
				}
			}
		}

		mdd.host.Text.free(face);

		says("every letter a language ships has a glyph", lost.length == 0,
			lost.length == 0
				? counted + " characters over " + shipped.length + " languages, the highest U+"
					+ StringTools.hex(widest, 4) + ", every one of them cut by the face"
				: lost.length + " the face has no glyph for: " + lost.slice(0, 4).join(", "));
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
