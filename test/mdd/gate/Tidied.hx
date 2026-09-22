package mdd.gate;

import mdd.song.Instrument;
import mdd.song.Library;
import mdd.song.Sample;
import mdd.song.Song;

/**
	Finds the files in a presets folder the library no longer offers, and removes them when told
	to.

		mdd gate tidy <presets folder> [--delete]

	A preset is read the way the application reads it and asked of the library that ships: a patch
	or an envelope whose sound is already there, whatever either is called, is a file that fills
	the browser with nothing. Lifting a piece's patches used to write one per preset the piece
	carried, and a piece carried the whole library, so a folder can be almost entirely copies.

	Nothing is removed without `--delete`, and a converter preset is never named at all, because a
	kit is picked by note out of one bank and a hit taken out is a key that stops sounding.
**/
class Tidied {
	/**
		@param args The presets folder, then `--delete` to act rather than to list.
		@return Nought where the folder was read.
	**/
	public static function run(args:Array<String>):Int {
		if (args.length < 1) {
			Sys.println("  tidy          tidy <presets folder> [--delete]");
			return 1;
		}

		final where = args[0];
		final acting = args.indexOf("--delete") >= 0;

		if (!sys.FileSystem.exists(where) || !sys.FileSystem.isDirectory(where)) {
			Sys.println("  tidy          no such folder: " + where);
			return 1;
		}

		final known = Gate.library();
		final held = new Song("starters");

		mdd.song.Shipped.into(held);

		for (index in 0...held.instruments.length) {
			final one = held.instrumentAt(index);
			if (one != null) known.adds(Library.STARTERS, one, null, false);
		}

		final spare:Array<String> = [];
		final kept:Array<String> = [];

		walked(where, known, spare, kept);

		var bytes = 0;

		for (path in spare) bytes += sys.FileSystem.stat(path).size;

		Sys.println("  tidy          " + (spare.length + kept.length) + " files, "
			+ spare.length + " of them a sound that already ships over " + bytes + " bytes, "
			+ kept.length + " the reader's own");

		for (path in kept) Sys.println("    keeping " + mdd.app.Files.name(path));

		if (!acting) {
			Sys.println("  tidy          nothing removed, pass --delete to remove them");
			return 0;
		}

		var gone = 0;

		for (path in spare) {
			try {
				sys.FileSystem.deleteFile(path);
				gone++;
			} catch (e:Dynamic) {
				Sys.println("    would not delete " + path + ": " + e);
			}
		}

		Sys.println("  tidy          " + gone + " removed, " + kept.length + " left");

		return 0;
	}

	/**
		Reads a folder and sorts its files into what the library already offers and what it does
		not.

		@param where The folder.
		@param known What ships.
		@param spare The files whose sound already ships.
		@param kept The files that carry something else.
	**/
	static function walked(where:String, known:Library, spare:Array<String>,
			kept:Array<String>):Void {
		for (name in sys.FileSystem.readDirectory(where)) {
			final path = where + "/" + name;

			if (sys.FileSystem.isDirectory(path)) {
				if (!StringTools.startsWith(name, ".")) walked(path, known, spare, kept);
				continue;
			}

			final lower = name.toLowerCase();

			if (!StringTools.endsWith(lower, Library.PATCH)
					&& !StringTools.endsWith(lower, Library.RECORDS)) {
				continue;
			}

			final one = read(path, lower);

			if (one == null || one.kind.sampled()) continue;

			if (offers(known, one)) spare.push(path);
			else kept.push(path);
		}
	}

	/**
		@param path A file in the presets folder.
		@param lower Its name in lower case.
		@return The one preset it holds, or null where it holds none or holds several.
	**/
	static function read(path:String, lower:String):Null<Instrument> {
		try {
			if (StringTools.endsWith(lower, Library.PATCH)) {
				final patch = mdd.format.Tfi.read(sys.io.File.getBytes(path));
				if (patch == null) return null;

				final out = new Instrument(mdd.app.Files.bare(path), mdd.song.Part.Fm1);

				out.patch = patch;
				return out;
			}

			final banked = mdd.format.Preset.read(sys.io.File.getBytes(path));
			if (banked == null || banked.presets.length != 1) return null;

			return banked.presets[0];
		} catch (e:Dynamic) {}

		return null;
	}

	/**
		@param known What ships.
		@param one A preset read out of the folder.
		@return Whether the library already makes that sound.
	**/
	static function offers(known:Library, one:Instrument):Bool {
		for (at in 0...known.names.length) {
			for (which in 0...known.instruments[at].length) {
				if (known.samples[at][which] != null) continue;
				if (Library.sounds(known.instruments[at][which], one)) return true;
			}
		}

		return false;
	}
}
