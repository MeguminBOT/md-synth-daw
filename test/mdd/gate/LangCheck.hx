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
		quick();

		for (code in shipped) spoken(code);

		matched(shipped);
		written(shipped);
		placed(shipped);
		filled();
		broken();
		drawable(shipped, args.length > 0 ? args[0] : Gate.root);
		scripted(args.length > 0 ? args[0] : Gate.root);
		crowded(args.length > 0 ? args[0] : Gate.root);

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	/**
		Checks where a line that does not fit is broken, in the scripts written with spaces and
		in the ones written without.
	**/
	static function broken():Void {
		final japanese = "オシレーターは 1 つだけなので";
		final room = japanese.indexOf("だ");
		final cut = mdd.ui.Font.breaks(japanese, room);

		says("kana breaks where the room runs out", cut == room,
			"at " + cut + " of " + room + ", with a space at " + japanese.indexOf(" "));

		final stop = "音量は無音です。次の段階";
		final mark = stop.indexOf("。");
		final kept = mdd.ui.Font.breaks(stop, mark);

		says("and a full stop stays on the line it closes", kept == mark - 1,
			"at " + kept + " where the stop is at " + mark);

		final korean = "채널 3은 네 음을 낼 수 있음";
		final hangul = korean.indexOf("음");
		final latin = "This language was translated";
		final spoken = mdd.ui.Font.breaks(korean, hangul);
		final written = mdd.ui.Font.breaks(latin, 12);

		says("korean and english still break between words",
			spoken == korean.lastIndexOf(" ", hangul) && written == latin.lastIndexOf(" ", 12),
			"at " + spoken + " and at " + written);
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;
		Sys.println("    " + StringTools.rpad(name, " ", 44) + said + (ok ? "" : "   FAILED"));
	}

	static function catalogue():Void {
		final held = new Translation();
		final taken = Languages.speak(held, Languages.first());

		says("the catalogue is what the reference language holds", taken == Locale.COUNT,
			Locale.COUNT + " ids generated against " + taken + " strings in "
				+ Languages.first());

		says("and an id is the position of its key", held.keyAt(Locale.APP) == "app"
			&& held.keyAt(Locale.WORKING_SAVING) == "working.saving",
			"app is " + (Locale.APP : Int) + ", working.saving is "
				+ (Locale.WORKING_SAVING : Int));
	}

	static function quick():Void {
		final held = new Translation();
		Languages.speak(held, Languages.first());

		final rounds = 500000;
		final began = haxe.Timer.stamp();

		var kept = 0;

		for (round in 0...rounds) {
			kept += held.of(Locale.APP).length;
			kept += held.of(Locale.MENU_FILE).length;
			kept += held.of(Locale.WORKING_SAVING).length;
			kept += held.of(Locale.THEME_SLATE).length;
		}

		final each = (haxe.Timer.stamp() - began) / (rounds * 4);

		final scans = 20000;
		final scanned = haxe.Timer.stamp();

		for (round in 0...scans) {
			kept += held.named("app").length;
			kept += held.named("menu.file").length;
			kept += held.named("working.saving").length;
			kept += held.named("theme.slate").length;
		}

		final slow = (haxe.Timer.stamp() - scanned) / (scans * 4);

		says("a lookup is an index rather than a scan", kept > 0 && each * 10 < slow,
			Math.round(each * 1000000000) + " ns by id against "
				+ Math.round(slow * 1000000000) + " ns by name over "
				+ Locale.COUNT + " keys");
	}

	static function spoken(code:String):Void {
		final held = new Translation();
		final taken = Languages.speak(held, code);

		final missing:Array<String> = [];

		for (id in 0...Locale.COUNT) {
			if (held.of(id) == "") missing.push(held.keyAt(id));
		}

		final apart = held.count() - Locale.COUNT;

		final said = taken + " strings"
			+ (missing.length == 0 ? "" : ", empty " + shown(missing))
			+ (apart == 0 ? "" : ", " + apart + " away from the catalogue");

		says(code, taken > 0 && missing.length == 0 && apart == 0, said);
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

	/**
		Loads the faces the interface bakes its sizes in, twice over the way a video export bakes
		its own beside them, and then the fallback chain, and asks that every fallback still loads.
		The chain on its own always fits, which is why the glyph checks above cannot see a fallback
		the interface has crowded out.

		@param root Where the fonts are.
	**/
	static function crowded(root:String):Void {
		final where = root + "/vendor/fonts/";
		final names = ["Go-Regular.ttf", "Go-Regular.ttf", "Go-Mono.ttf", "Go-Mono.ttf",
			mdd.Typeface.CONDENSED];

		final own:Array<Int> = [];
		final chain:Array<Int> = [];

		for (round in 0...2) {
			for (name in names) {
				if (name == "" || !sys.FileSystem.exists(where + name)) continue;

				final face = mdd.host.Text.load(where + name);
				if (face >= 0) own.push(face);
			}
		}

		var wanted = 0;

		for (name in mdd.Typeface.FALLBACK) {
			if (!sys.FileSystem.exists(where + name)) continue;

			wanted++;

			final face = mdd.host.Text.load(where + name);
			if (face >= 0) chain.push(face);
		}

		for (face in own) mdd.host.Text.free(face);
		for (face in chain) mdd.host.Text.free(face);

		says("every fallback loads beside the interface", wanted > 0 && chain.length == wanted,
			own.length + " interface faces held, then " + chain.length + " of " + wanted
			+ " fallback faces loaded");
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
		final faces = chain(root);

		if (faces.length == 0) {
			says("every letter a language ships can be drawn", false, "no faces to ask");
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
				final said = held.of(index);

				var at = 0;

				while (at < said.length) {
					final one = mdd.ui.Font.codeAt(said, at);
					at += mdd.ui.Font.step(one);

					counted++;
					if (one > widest) widest = one;

					if (covers(faces, one, wide, tall)) continue;

					final shown = code + " " + key + " U+" + StringTools.hex(one, 4);
					if (lost.indexOf(shown) < 0) lost.push(shown);
				}
			}
		}

		for (face in faces) mdd.host.Text.free(face);

		says("every letter a language ships has a glyph", lost.length == 0,
			lost.length == 0
				? counted + " characters over " + shipped.length + " languages, the highest U+"
					+ StringTools.hex(widest, 4) + ", every one of them cut by the chain of "
					+ faces.length + " faces"
				: lost.length + " with no glyph anywhere: " + lost.slice(0, 4).join(", "));
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

		for (id in 0...Locale.COUNT) {
			if (english.of(id) != swedish.of(id)) translated++;
		}

		says("and a language is a language", translated > Std.int(Locale.COUNT / 2),
			translated + " of " + Locale.COUNT
			+ " strings differ between en-GB and sv-SE, so it is a translation and not a copy");

		says("a hardware name is never translated",
			english.of(Locale.APP) == swedish.of(Locale.APP)
			&& swedish.of(Locale.VIEW_TRACKER) == "Tracker",
			"the application's name and the hardware words stay as the documentation writes them");
	}

	/**
		Every language says whether a machine translated it or a person wrote it, in
		one of two words rather than in a sentence, because the welcome sheet reads it
		to pick which line to show rather than showing it. A word translated along
		with everything else around it would read as a language nobody wrote.

		@param shipped Every language compiled in.
	**/
	static function written(shipped:Array<String>):Void {
		final odd:Array<String> = [];

		var machine = 0;
		var person = 0;

		for (code in shipped) {
			final held = new Translation();
			Languages.speak(held, code);

			final said = held.of(Locale.LANGUAGE_WRITTEN);

			if (said == "machine") machine++;
			else if (said == "person") person++;
			else odd.push(code + " says '" + said + "'");

			if (held.of(Locale.LANGUAGE_MACHINE) == held.of(Locale.LANGUAGE_PERSON)) {
				odd.push(code + " says the same either way");
			}
		}

		says("every language says whether a machine wrote it",
			odd.length == 0 && machine > 0 && person > 0,
			odd.length > 0 ? shown(odd)
				: machine + " machine translated, " + person + " written by a person");
	}

	/**
		Every language leaves the same numbered places as the reference.

		A line that drops one loses the value that went in it, and one that invents
		a place it has no value for shows the braces to a reader. Neither says
		anything at run time, and neither is visible until somebody reads that
		language.

		@param shipped Every language compiled in.
	**/
	static function placed(shipped:Array<String>):Void {
		final first = new Translation();
		Languages.speak(first, shipped[0]);

		final lost:Array<String> = [];
		var counted = 0;

		for (at in 1...shipped.length) {
			final held = new Translation();
			Languages.speak(held, shipped[at]);

			for (id in 0...Locale.COUNT) {
				final want = places(first.of(id));
				if (want == "") continue;

				counted++;
				if (places(held.of(id)) == want) continue;

				lost.push(shipped[at] + " " + first.keyAt(id));
			}
		}

		says("every language leaves the same places for its values",
			lost.length == 0 && counted > 0,
			counted + " lines across " + (shipped.length - 1)
			+ " languages carry values, and "
			+ (lost.length == 0 ? "every one leaves the same places"
			: lost.length + " disagree: " + shown(lost)));
	}

	/**
		@param said A line from the table.
		@return The numbers of the places it leaves, in order and without repeats, so
			two lines can be compared whatever order they put their values in.
	**/
	static function places(said:String):String {
		final held:Array<Int> = [];
		var at = 0;

		while (at < said.length) {
			final open = said.indexOf("{", at);
			final shut = open < 0 ? -1 : said.indexOf("}", open);

			if (open < 0 || shut < 0) break;

			final which = Std.parseInt(said.substring(open + 1, shut));
			if (which != null && held.indexOf(which) < 0) held.push(which);

			at = shut + 1;
		}

		held.sort(function(one:Int, two:Int):Int return one - two);
		return held.join(",");
	}

	/**
		Filling a line puts each value in its own place, whatever order the sentence
		puts them in, and leaves alone what it has nothing for.
	**/
	static function filled():Void {
		final held = ["one", "two"];

		says("a value goes where its own place is",
			Translation.filled("read {0}, {1} notes", held) == "read one, two notes"
			&& Translation.filled("{1} notes in {0}", held) == "two notes in one",
			"the same two values read back in either order");

		says("and a place with nothing behind it is left as it stands",
			Translation.filled("{0} of {7}", held) == "one of {7}"
			&& Translation.filled("{0}", []) == "{0}"
			&& Translation.filled("plain", held) == "plain",
			"a line is readable rather than blank where a value is missing");
	}

	static function shown(held:Array<String>):String {
		if (held.length <= 4) return held.join(", ");
		return held.slice(0, 4).join(", ") + " and " + (held.length - 4) + " more";
	}
}
