package mdd.gate;

import mdd.format.Json;
import mdd.format.Node;

@:unreflective
class JsonCheck {
	static var ran = 0;
	static var failed = 0;

	static final TRICKY:Array<String> = [
		"{\"a\":1,\"b\":-2.5,\"c\":1e3,\"d\":-1.5E-2}",
		"{\"t\":true,\"f\":false,\"n\":null}",
		"{\"s\":\"plain\",\"e\":\"a\\\"b\\\\c\\/d\",\"w\":\"x\\ty\\nz\"}",
		"{\"u\":\"\\u0041\\u00e9\\u20ac\"}",
		"[1,[2,[3,[4]]]]",
		"{\"deep\":{\"deeper\":{\"deepest\":[1,2,3]}}}",
		"[]",
		"{}",
		"{\"empty\":\"\"}",
		"[0,-0,0.0,1000000,123456789]"
	];

	public static function run(args:Array<String>):Int {
		ran = 0;
		failed = 0;

		Sys.println("  json");

		agreed();
		timed();
		banked();

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");
		Sys.println(failed == 0 ? "    passed" : "    failed");

		return failed == 0 ? 0 : 1;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 42) + said + (ok ? "" : "   FAILED"));
	}

	static function agreed():Void {
		var apart = 0;
		var first = "";

		for (said in TRICKY) {
			final ours = Json.parse(said);
			final theirs:Dynamic = haxe.Json.parse(said);

			if (same(ours, theirs)) continue;

			apart++;
			if (first == "") first = said;
		}

		says("both parsers read the same documents", apart == 0,
			apart == 0 ? TRICKY.length + " documents read the same by each"
				: apart + " of " + TRICKY.length + " disagree, the first being " + first);
	}

	static function same(ours:Node, theirs:Dynamic):Bool {
		if (theirs == null) return ours.shape == Node.NOTHING;

		if (Std.isOfType(theirs, Bool)) {
			return ours.shape == Node.FLAG && ours.truth(false) == (theirs == true);
		}

		if (Std.isOfType(theirs, Float) || Std.isOfType(theirs, Int)) {
			if (ours.shape != Node.NUMBER) return false;

			final want:Float = theirs;
			final gap = ours.number - want;

			return (gap < 0 ? -gap : gap) < 1e-9;
		}

		if (Std.isOfType(theirs, String)) {
			return ours.shape == Node.TEXT && ours.text == (theirs : String);
		}

		if (Std.isOfType(theirs, Array)) {
			final held:Array<Dynamic> = theirs;
			if (ours.shape != Node.LIST || ours.values.length != held.length) return false;

			for (index in 0...held.length) if (!same(ours.values[index], held[index])) return false;
			return true;
		}

		if (ours.shape != Node.TABLE) return false;

		final fields = Reflect.fields(theirs);
		if (fields.length != ours.keys.length) return false;

		for (name in fields) {
			final at = ours.keys.indexOf(name);
			if (at < 0) return false;
			if (!same(ours.values[at], Reflect.field(theirs, name))) return false;
		}

		return true;
	}

	/**
		A bank written here reads back as what went in.

		Nothing in the application could write one until now: every bank that ships was
		made by a program outside it, so the reader had never been held to a writer.
	**/
	static function banked():Void {
		final made:Array<mdd.song.Instrument> = [];
		final held:Array<Null<mdd.song.Sample>> = [];

		final names = ["Kick", "Snare"];
		final roots = [36, 38];
		final rates = [11025, 14000];

		for (which in 0...names.length) {
			final one = new mdd.song.Instrument(names[which], mdd.song.Part.Dac);

			one.icon = mdd.Icon.NAMES.indexOf("kick");
			one.tags.push("Drums");
			one.tags.push("Percussion");

			final sample = new mdd.song.Sample(names[which], rates[which], roots[which]);
			final bytes = new haxe.ds.Vector<Int>(600 + which);

			for (at in 0...bytes.length) bytes[at] = (at * 7 + which * 31) & 0xFF;

			sample.hold(bytes);

			made.push(one);
			held.push(sample);
		}

		final said = mdd.song.Library.written("A Kit", made, held);
		final back = new mdd.song.Library();
		final many = back.reads(said);

		says("a bank written here reads back", many == 2 && back.names.length == 1
			&& back.names[0] == "A Kit",
			many + " presets in a bank called '" + (back.names.length == 0 ? "" 
				: back.names[0]) + "', from " + said.length + " bytes of document");

		var same = many == 2;
		var apart = "";

		if (same) {
			for (which in 0...names.length) {
				final one = back.instruments[0][which];
				final sample = back.samples[0][which];

				if (sample == null) {
					same = false;
					apart = names[which] + " came back with no sample";
					break;
				}

				if (one.name != names[which] || one.icon != made[which].icon
					|| one.tags.length != 2 || sample.root != roots[which]
					|| sample.rate != rates[which]
					|| sample.length() != held[which].length()) {
					same = false;
					apart = names[which] + " came back different";
					break;
				}

				for (at in 0...sample.length()) {
					if (sample.bytes[at] == held[which].bytes[at]) continue;

					same = false;
					apart = names[which] + " differs at byte " + at;
					break;
				}

				if (!same) break;
			}
		}

		says("and every byte of it is what went in", same,
			same ? "the name, the icon, the tags, the root, the rate and all "
				+ (held[0].length() + held[1].length()) + " bytes of both hits" : apart);
	}

	static function timed():Void {
		final root = Gate.root;

		final files = [root + "/assets/presets/sonic-the-hedgehog-2.json",
			root + "/assets/lang/en-GB.json"];

		final names = ["a shipped bank", "a language"];

		for (index in 0...files.length) {
			if (!sys.FileSystem.exists(files[index])) continue;

			final said = sys.io.File.getContent(files[index]);
			final rounds = said.length > 200000 ? 20 : 200;

			var sink = 0.0;

			final oursAt = haxe.Timer.stamp();
			for (turn in 0...rounds) sink += Json.parse(said).keys.length;
			final ours = haxe.Timer.stamp() - oursAt;

			final theirsAt = haxe.Timer.stamp();
			for (turn in 0...rounds) sink += Reflect.fields(haxe.Json.parse(said)).length;
			final theirs = haxe.Timer.stamp() - theirsAt;

			final each = ours / rounds * 1000;
			final other = theirs / rounds * 1000;

			says(names[index] + " parses", sink > 0,
				Math.round(said.length / 1024) + " kb, ours " + round(each)
				+ " ms against " + round(other) + " ms, "
				+ (each < other ? round(other / each) + " times faster"
					: round(each / other) + " times slower"));
		}
	}

	static function round(value:Float):Float {
		return Math.round(value * 100) / 100;
	}
}
