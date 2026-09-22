import sys.FileSystem;

/**
	Turns the banks the application ships into the format it reads them in.

	The banks are kept as documents, because that is what anyone improving a name or a tag opens,
	and a build writes each one out as records for the application to carry. Nothing is written by
	hand in the built form, so the two cannot drift.

	The starting bank is the one compiled into the application, so its documents are written into
	one folder, one records file each, and every document naming it adds to the same bank. Every
	other bank ships as files beside the application, which a reader may delete, so each is written
	into a second folder under the family folders a presets folder is laid out in, one file per
	family, since a family's folder is where the application puts it.

	Usage: haxe -cp src -cp tools/src --run Banker <folder of documents> <folder compiled in>
		<folder shipped beside>
**/
class Banker {
	static function main():Void {
		final args = Sys.args();

		if (args.length < 3) {
			Sys.println("mdd: banker takes a folder of bank documents, a folder for the bank compiled in"
				+ " and a folder for the banks shipped beside it");
			Sys.exit(1);
		}

		Sys.exit(built(args[0], args[1], args[2]));
	}

	/**
		@param from The folder of bank documents.
		@param into The folder the starting bank's records go into, made where it is not there.
		@param beside The folder every other bank's records go into, by family, made where it is
			not there.
		@return Nought where every document was written out.
	**/
	public static function built(from:String, into:String, beside:String):Int {
		if (!FileSystem.exists(from) || !FileSystem.isDirectory(from)) return 0;
		if (!FileSystem.exists(into)) FileSystem.createDirectory(into);

		final held = FileSystem.readDirectory(from);
		held.sort(function(one:String, two:String):Int return one < two ? -1 : 1);

		for (name in held) {
			if (!StringTools.endsWith(name.toLowerCase(), mdd.song.Library.SUFFIX)) continue;

			final library = new mdd.song.Library();
			final read = library.reads(sys.io.File.getContent(from + "/" + name));

			if (read == 0 || library.names.length == 0) {
				Sys.println("mdd: nothing in " + name);
				return 1;
			}

			final stem = name.substr(0, name.length - mdd.song.Library.SUFFIX.length);

			for (at in 0...library.names.length) {
				final bank = library.names[at];

				if (bank == mdd.song.Library.STARTERS) {
					sys.io.File.saveBytes(into + "/" + stem + mdd.format.Preset.BANK,
						mdd.format.Preset.write(bank, library.instruments[at], library.samples[at]));

					continue;
				}

				for (family in mdd.song.Library.FAMILIES) {
					final presets:Array<mdd.song.Instrument> = [];
					final samples:Array<Null<mdd.song.Sample>> = [];

					for (which in 0...library.instruments[at].length) {
						final one = library.instruments[at][which];
						if (one.kind.family() != family) continue;

						presets.push(one);
						samples.push(library.samples[at][which]);
					}

					if (presets.length == 0) continue;

					final folder = beside + "/" + family;
					made(folder);

					sys.io.File.saveBytes(folder + "/" + safely(bank) + mdd.format.Preset.BANK,
						mdd.format.Preset.write(bank, presets, samples));
				}
			}
		}

		return 0;
	}

	/**
		Makes a folder and every folder above it.

		@param where The folder.
	**/
	static function made(where:String):Void {
		if (where == "" || FileSystem.exists(where)) return;

		final parent = haxe.io.Path.directory(where);
		if (parent != "" && parent != where) made(parent);

		FileSystem.createDirectory(where);
	}

	/**
		@param said A bank's name.
		@return It with anything a file name cannot carry made a dash.
	**/
	static function safely(said:String):String {
		final out = new StringBuf();

		for (index in 0...said.length) {
			final one = said.charAt(index);
			out.add("/\\:*?\"<>|".indexOf(one) >= 0 ? "-" : one);
		}

		return StringTools.trim(out.toString());
	}
}
