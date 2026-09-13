package mdd.gate;

import mdd.format.Kit;

@:unreflective

/**
	Turns a folder of recordings into a bank the converter can play, and says what it
	did with each one.

	It is the same `mdd.format.Kit` the sheet drives, run from a shell instead of a
	window, which is what lets a kit be checked against its own recordings without one
	open. It writes a file, so the gate does not run it.
**/
class Converted {
	/**
		@param args The folder to read, the file to write, and optionally a rate.
		@return Nought where it wrote.
	**/
	public static function run(args:Array<String>):Int {
		if (args.length < 2) {
			Sys.println("  convert       mdd gate convert <folder> <file> [rate]");
			return 1;
		}

		final kit = new Kit();

		if (args.length > 2) {
			final want = Std.parseInt(args[2]);
			if (want != null && want > 0) kit.rate = want;
		}

		final many = kit.reads(args[0]);

		if (many == 0) {
			Sys.println("  convert       no wave files in " + args[0]);
			return 1;
		}

		kit.detects();
		kit.converts();

		final said = kit.written();

		if (said == "") {
			Sys.println("  convert       nothing converted");
			return 1;
		}

		sys.io.File.saveContent(args[1], said);

		Sys.println("  convert       " + kit.name + ", " + many + " hits at " + kit.rate
			+ " Hz");

		for (slot in kit.slots) {
			final made = slot.made;

			Sys.println("    " + StringTools.rpad(slot.name, " ", 22)
				+ "key " + StringTools.rpad("" + slot.root, " ", 5)
				+ StringTools.lpad("" + (made == null ? 0 : made.length()), " ", 7) + " bytes  "
				+ round(made == null ? 0 : made.length() / kit.rate) + " s  from "
				+ round(slot.seconds) + " s at " + slot.was + " Hz, "
				+ Math.round(slot.pitch) + " Hz, rings " + round(slot.rings) + " s");
		}

		final bytes = kit.bytes();
		final room = mdd.check.Profile.ROM;

		Sys.println("    " + bytes + " bytes, " + Math.round(bytes * 1000.0 / room) / 10.0
			+ " per cent of the " + room + " a quarter of a megabyte cartridge holds"
			+ (bytes > room ? ", which is over it" : ""));

		Sys.println("    written to " + args[1]);
		return 0;
	}

	static function round(value:Float):Float {
		return Math.round(value * 1000) / 1000;
	}
}
