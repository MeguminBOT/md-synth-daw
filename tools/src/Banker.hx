import sys.FileSystem;

/**
	Turns the banks the application ships into the format it reads them in.

	The banks are kept as documents, because that is what anyone improving a name or a tag opens,
	and a build writes each one out as records for the application to carry. Nothing is written by
	hand in the built form, so the two cannot drift.

	Usage: haxe -cp src -cp tools/src --run Banker <folder of documents> <folder to write>
**/
class Banker {
	static function main():Void {
		final args = Sys.args();

		if (args.length < 2) {
			Sys.println("mdd: banker takes a folder of bank documents and a folder to write");
			Sys.exit(1);
		}

		Sys.exit(built(args[0], args[1]));
	}

	/**
		@param from The folder of bank documents.
		@param into The folder to write the records into, made where it is not there.
		@return Nought where every document was written out.
	**/
	public static function built(from:String, into:String):Int {
		if (!FileSystem.exists(from) || !FileSystem.isDirectory(from)) return 0;
		if (!FileSystem.exists(into)) FileSystem.createDirectory(into);

		final held = FileSystem.readDirectory(from);
		held.sort(function(one:String, two:String):Int return one < two ? -1 : 1);

		var many = 0;

		for (name in held) {
			if (!StringTools.endsWith(name.toLowerCase(), mdd.song.Library.SUFFIX)) continue;

			final library = new mdd.song.Library();
			final read = library.reads(sys.io.File.getContent(from + "/" + name));

			if (read == 0 || library.names.length == 0) {
				Sys.println("mdd: nothing in " + name);
				return 1;
			}

			for (at in 0...library.names.length) {
				final written = mdd.format.Preset.write(library.names[at], library.instruments[at],
					library.samples[at]);

				final stem = name.substr(0, name.length - mdd.song.Library.SUFFIX.length);
				sys.io.File.saveBytes(into + "/" + stem + mdd.format.Preset.BANK, written);

				many++;
			}
		}

		return many > 0 ? 0 : 0;
	}
}
