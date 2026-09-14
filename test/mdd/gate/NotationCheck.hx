package mdd.gate;

import mdd.song.Notation;

@:unreflective

/**
	Note names in all four styles: every pitch spelt and read back, the tracker's padded cells read
	back, and the letters that mean different notes in English and in German.
**/
class NotationCheck {
	static var failed:Int = 0;
	static var ran:Int = 0;

	static final STYLES:Array<String> = ["English sharps", "English flats", "German sharps",
		"German flats"];

	/**
		@param args The gate's arguments, unused.
		@return Nought where every check held.
	**/
	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  notation");

		for (style in 0...4) returned(style);

		final english = Notation.styled(Notation.SHARPS, Notation.ENGLISH);
		final german = Notation.styled(Notation.FLATS, Notation.GERMAN);

		says("German H is B natural and B is B flat",
			Notation.read("H4", german) == 71 && Notation.read("B4", german) == 70
				&& Notation.spelt(71, german) == "H4" && Notation.spelt(70, german) == "B4",
			"H4 reads " + Notation.read("H4", german) + ", B4 reads " + Notation.read("B4", german)
				+ ", 71 is " + Notation.spelt(71, german) + " and 70 is " + Notation.spelt(70, german));

		says("English B is B natural and H is no note",
			Notation.read("B4", english) == 71 && Notation.read("H4", english) == -1
				&& Notation.read("Bb4", english) == 70,
			"B4 reads " + Notation.read("B4", english) + ", H4 reads "
				+ Notation.read("H4", english) + " and Bb4 reads " + Notation.read("Bb4", english));

		says("flats spell a lowered note and cells pad a natural",
			Notation.spelt(61, Notation.styled(Notation.FLATS, Notation.ENGLISH)) == "Db4"
				&& Notation.cell(60, english) == "C-4" && Notation.cell(128, english) == "---",
			"61 is " + Notation.spelt(61, Notation.styled(Notation.FLATS, Notation.ENGLISH))
				+ ", 60 fills a cell as " + Notation.cell(60, english) + " and 128 as "
				+ Notation.cell(128, english));

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	/**
		Spells every MIDI pitch in a style, as a name and as a cell, and reads both back.

		@param style Which style.
	**/
	static function returned(style:Int):Void {
		var lost = 0;
		var first = "";

		for (pitch in 0...128) {
			final spelt = Notation.spelt(pitch, style);
			final cell = Notation.cell(pitch, style);

			if (Notation.read(spelt, style) == pitch && Notation.read(cell, style) == pitch) continue;
			if (pitch < 12 && Notation.read(spelt, style) != pitch) continue;

			lost++;
			if (first == "") first = pitch + " as " + spelt + " and " + cell;
		}

		says(STYLES[style] + " read back", lost == 0,
			lost == 0 ? "every pitch from 12 to 127 spelt and read back as itself"
				: lost + " did not, the first " + first);
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 52) + said + (ok ? "" : "   FAILED"));
	}
}
