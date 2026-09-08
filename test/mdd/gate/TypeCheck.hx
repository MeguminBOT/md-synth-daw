package mdd.gate;

import haxe.ds.Vector;
import mdd.Typeface;
import mdd.host.Text;

@:unreflective
class TypeCheck {
	static inline final TALL = 128;
	static inline final ROOM = 512;

	static inline final THINNEST = 0.055;
	static inline final THICKEST = 0.150;

	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  type");

		final where = fonts(args.length > 0 ? args[0] : Gate.root);

		if (where == "") {
			Sys.println("    no fonts found. Run: mdd setup");
			return 1;
		}

		final named:Array<String> = [];

		for (list in [Typeface.SANS, Typeface.MONO, Typeface.FALLBACK]) {
			for (name in list) {
				if (named.indexOf(name) < 0) named.push(name);
			}
		}

		Sys.println("    " + StringTools.rpad("face", " ", 26)
			+ StringTools.rpad("weight", " ", 9)
			+ StringTools.rpad("stem", " ", 8)
			+ StringTools.rpad("load", " ", 9) + "of the cap");

		for (name in named) measured(where + "/" + name, name);

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	static function fonts(root:String):String {
		for (where in [root + "/vendor/fonts", Sys.getCwd() + "/vendor/fonts",
				root + "/export/bin/fonts"]) {
			if (sys.FileSystem.exists(where + "/Go-Regular.ttf")) {
				return haxe.io.Path.normalize(where);
			}
		}

		return "";
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;
		Sys.println("    " + StringTools.rpad(name, " ", 26) + said + (ok ? "" : "   FAILED"));
	}

	static function measured(path:String, name:String):Void {
		if (!sys.FileSystem.exists(path)) {
			says(name, false, "missing");
			return;
		}

		final began = haxe.Timer.stamp();
		final face = Text.load(path);
		final took = (haxe.Timer.stamp() - began) * 1000;

		if (face < 0) {
			says(name, false, "would not load");
			return;
		}

		final weight = Text.weight(face);
		final resting = Text.resting(face);
		final stem = stemmed(face);

		Text.free(face);

		final held = stem < 0 ? "no cap" : Std.string(Math.round(stem * 10000) / 10000);

		final rests = resting == 0 || resting == 400;

		says(name, weight == 400 && rests && stem >= THINNEST && stem <= THICKEST,
			StringTools.rpad(Std.string(weight), " ", 9)
			+ StringTools.rpad(held, " ", 8)
			+ StringTools.rpad(Std.string(Math.round(took * 10) / 10) + " ms", " ", 9)
			+ (!rests ? "its axis still rests at " + resting
				: stem < 0 ? "no stem to measure"
				: stem < THINNEST ? "too thin for a regular"
				: stem > THICKEST ? "too thick for a regular" : "reads as a regular"));
	}

	static function stemmed(face:Int):Float {
		final wide:Vector<Int> = new Vector<Int>(1);
		final tall:Vector<Int> = new Vector<Int>(1);

		if (Text.extent(face, TALL, "H".code, cpp.Pointer.arrayElem(wide.toData(), 0).raw,
			cpp.Pointer.arrayElem(tall.toData(), 0).raw) == 0) return -1;

		final across = wide[0];
		final down = tall[0];

		if (across <= 0 || down <= 0 || across > ROOM || down > ROOM) return -1;

		final pixels:Vector<cpp.UInt8> = new Vector<cpp.UInt8>(across * down * 4);
		final glyph:Vector<Single> = new Vector<Single>(16);

		if (Text.glyph(face, TALL, "H".code, cpp.Pointer.arrayElem(pixels.toData(), 0).raw,
			across, down, 0, 0, cpp.Pointer.arrayElem(glyph.toData(), 0).raw) == 0) return -1;

		final row = down / 5 < 1 ? 0 : Std.int(down / 5);
		var run = 0;
		var most = 0;
		var seen = 0;

		for (column in 0...across) {
			final lit = pixels[(row * across + column) * 4 + 3] >= 128;

			if (lit) {
				run++;
				if (run > most) most = run;
				continue;
			}

			if (run > 0) seen++;
			run = 0;
		}

		if (run > 0) seen++;
		if (seen < 2 || most <= 0) return -1;

		return most / down;
	}
}
