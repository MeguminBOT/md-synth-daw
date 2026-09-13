package mdd.gate;

import haxe.ds.Vector;
import mdd.format.Kit;
import sys.FileSystem;

@:unreflective

/**
	What a kit makes of the names its recordings carry.

	A pack of pitched samples names every key, `A#3` beside `A3`, and every one of them was
	laid out one key after another in the order the names compared as text. The sheet put
	such a pack on keys that had nothing to do with its names, and put `Hit 10` between
	`Hit 1` and `Hit 2`. Nothing here opens a window or a sound device.
**/
class KitCheck {
	static var failed:Int = 0;
	static var ran:Int = 0;

	/**
		@param args The gate's arguments, unused.
		@return Nought where every check held.
	**/
	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  keys");

		spelt();
		sorted();
		pitched();
		drummed();

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	/**
		A note is read out of a name however the name writes it, and out of nothing that
		only looks like one.
	**/
	static function spelt():Void {
		final names = ["BF – A#3", "BF - A3", "Lead E♭4", "Pad A♯3", "C-4",
			"Piano c#5", "Choir G3 G4"];

		final keys = [for (name in names) Kit.noteIn(name)].join(" ");

		says("a note is read however a name spells it", keys == "58 57 63 58 60 73 67",
			"an en dash, a plain dash, a flat sign, a sharp sign, a tracker dash, lower case"
			+ " and two notes in one name read " + keys + " against 58 57 63 58 60 73 67");

		final loose = ["BD2", "SD1", "Tom 1", "Kick", "Hit 10", "B9"];
		final none = [for (name in loose) Kit.noteIn(name)].join(" ");

		says("and nothing that only looks like one is", none == "-1 -1 -1 -1 -1 -1",
			"BD2, SD1, Tom 1, Kick, Hit 10 and B9, which is past key 127, read " + none);
	}

	/**
		Names sort the way they read rather than the way their characters compare.
	**/
	static function sorted():Void {
		final names = ["Hit 10", "Hit 2", "Hit 1", "Hit 20", "Hit 11", "Hit", "hit 3"];
		names.sort(function(one:String, two:String):Int return Kit.inOrder(one, two));

		final said = names.join(", ");

		says("names sort the way they read", said == "Hit, Hit 1, Hit 2, hit 3, Hit 10, Hit 11, Hit 20",
			said);
	}

	/**
		A pack of pitched samples lands on the keys its names spell, the rest follow in the
		order their names read, and the list is left low to high.
	**/
	static function pitched():Void {
		final where = emptied("kit-names");

		for (name in ["BF - A#3", "BF - A3", "BF - C#5", "BF - B4", "Hit 10", "Hit 2", "Hit 1"]) {
			written(where + "/" + name + ".wav");
		}

		final kit = new Kit();
		kit.drums = false;

		final read = kit.reads(where);
		kit.detects();

		final named = keyOf(kit, "BF - A3") + " " + keyOf(kit, "BF - A#3") + " "
			+ keyOf(kit, "BF - B4") + " " + keyOf(kit, "BF - C#5");

		says("a hit lands on the key its name spells", read == 7 && named == "57 58 71 73",
			read + " files read, and A3, A#3, B4 and C#5 landed on " + named
			+ " against 57 58 71 73");

		final counted = keyOf(kit, "Hit 1") + " " + keyOf(kit, "Hit 2") + " "
			+ keyOf(kit, "Hit 10");

		says("and the rest follow in the order their names read", counted == "36 37 38",
			"Hit 1, Hit 2 and Hit 10 landed on " + counted);

		final order = [for (slot in kit.slots) slot.name].join(", ");

		says("and the list reads low to high",
			order == "Hit 1, Hit 2, Hit 10, BF - A3, BF - A#3, BF - B4, BF - C#5", order);
	}

	/**
		With drums on, a name that spells a note still says where it goes, and a name that
		does not is still read for its family.
	**/
	static function drummed():Void {
		final where = emptied("kit-drums");

		written(where + "/Kick.wav");
		written(where + "/Snare E2.wav");

		final kit = new Kit();

		kit.reads(where);
		kit.detects();

		final kick = keyOf(kit, "Kick");
		final snare = keyOf(kit, "Snare E2");

		says("with drums on a spelt note still wins", kick == 36 && snare == 40,
			"the kick landed on " + kick + " by its family and the snare called E2 on " + snare
			+ " by its name, where a snare would otherwise take 38");
	}

	/**
		@param name A folder under export.
		@return Its path, with every file already in it taken away.
	**/
	static function emptied(name:String):String {
		final where = Gate.root + "/export/" + name;
		mdd.host.Paths.make(where);

		for (file in FileSystem.readDirectory(where)) {
			if (!FileSystem.isDirectory(where + "/" + file)) FileSystem.deleteFile(where + "/" + file);
		}

		return where;
	}

	/**
		Writes a twentieth of a second of noise, which is all a key needs to be given.

		@param path Where to write it.
	**/
	static function written(path:String):Void {
		final rate = 22050;
		final frames = Std.int(rate / 20);
		final held = new Vector<cpp.Float32>(frames);

		var seed = 0x4B49;

		for (index in 0...frames) {
			seed = (seed * 1103515245 + 12345) & 0x3FFFFFFF;
			held[index] = 0.5 * (((seed >> 8) % 2000) - 1000) / 1000.0;
		}

		sys.io.File.saveBytes(path, mdd.format.Wav.write(held, frames, 1, rate, 16, false));
	}

	/**
		@param kit The kit.
		@param called What a hit is called.
		@return Which key it landed on, or -1 where there is no such hit.
	**/
	static function keyOf(kit:Kit, called:String):Int {
		for (slot in kit.slots) if (slot.name == called) return slot.root;

		return -1;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 34) + said + (ok ? "" : "   FAILED"));
	}
}
