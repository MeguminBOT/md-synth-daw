package mdd.gate;

import mdd.format.Needed;
import mdd.format.Project;
import mdd.song.Instrument;
import mdd.song.Library;
import mdd.song.Sample;
import mdd.song.Song;

/**
	Reads finished pieces' own presets out of their project files and writes them as bank
	documents, which is the form `assets/presets` is edited in and the build turns into records.

		mdd gate bank <into folder> <presets folder> <project>[=kit name]...

	What comes out of a piece is what it plays and nobody else already offers: a preset a shipped
	bank or the set every piece begins with already has is left out, and so is a hit whose
	recording is already shipped under the same name, because shipping the bytes twice buys
	nothing. A presets folder named on the command line is left out the same way, which is how
	anything that arrived from somewhere else stays out of what ships: a `-` in its place reads
	no folder. The kit behind the sample channel comes whole, because a hit is picked by note out of
	a bank rather than named.

	Everything that is not a recording goes into the default bank, the set every piece begins with,
	rather than into a bank per piece: a preset is a preset, and a browser of one category per
	track is a browser nobody reads. A recording cannot go there, because a hit is picked by note
	out of the bank the rack's converter preset sits in, and five kicks on key 36 in one bank means
	four of them never sound. Each piece's hits therefore become a kit of their own, named for what
	the kit is on the command line.

	A preset arrives tagged with every piece it came out of, so a search still finds everything
	from one track at once.
**/
class Lifted {
	/**
		What the bank every piece begins with is called, which is where everything that is not a
		recording goes.
	**/
	static inline final DEFAULT = Library.STARTERS;

	/**
		@param args The folder to write into, a presets folder to leave out or `-`, then the
			project files, each of which may carry `=` and what to call the kit it brings.
		@return Nought where every piece was read.
	**/
	public static function run(args:Array<String>):Int {
		if (args.length < 3) {
			Sys.println("  bank          bank <into folder> <presets folder> <project>[=kit]...");
			return 1;
		}

		final folder = args[0];
		final known = Library.embedded();

		if (args[1] != "-") known.within(args[1], Library.STARTERS);

		mdd.host.Paths.make(folder);

		final keys:Array<String> = [];
		final presets:Array<Instrument> = [];
		final played:Array<Null<Sample>> = [];
		final sources:Array<Array<String>> = [];
		final banks:Array<String> = [];

		for (index in 2...args.length) {
			final said = args[index];
			final at = said.lastIndexOf("=");

			final where = at > 1 ? said.substring(0, at) : said;
			final kit = at > 1 ? said.substring(at + 1) : "";

			if (!sys.FileSystem.exists(where)) {
				Sys.println("  bank          no such file: " + where);
				return 1;
			}

			read(where, kit, known, keys, presets, played, sources, banks);
		}

		return wrote(folder, presets, played, sources, banks);
	}

	/**
		Reads one piece and puts what is its own into the gathered set.

		@param where The project file.
		@param kit What to call the kit it brings, or an empty string to name it after the file.
		@param known What already ships and what arrived from somewhere else.
		@param keys What each gathered preset holds, as an identity with no tag in it.
		@param presets The gathered presets.
		@param played What each one plays, or null.
		@param sources Which pieces each one came out of.
		@param banks Which bank each gathered preset goes in.
	**/
	static function read(where:String, kit:String, known:Library, keys:Array<String>,
			presets:Array<Instrument>, played:Array<Null<Sample>>,
			sources:Array<Array<String>>, banks:Array<String>):Void {
		final song = Project.open(where);
		final title = mdd.app.Files.bare(where);
		final named = kit == "" ? title + " Kit" : kit;

		final starting = starters();
		final needed = Needed.of(song);

		var own = 0;
		var hits = 0;
		var shared = 0;

		for (index in 0...song.instruments.length) {
			if (needed.instrument(index) < 0) continue;

			final one = song.instruments[index];
			final sample = one.sample < 0 ? null : song.sampleAt(one.sample);

			if (known.offering(song, one) != "" || starting.offering(song, one) != ""
					|| sounded(known, one, sample)) {
				shared++;
				continue;
			}

			final copy = one.copy();

			copy.sample = -1;
			copy.from = "";
			copy.tags.resize(0);
			copy.id = "";

			final key = copy.identifies(sample);
			final at = keys.indexOf(key);

			if (at >= 0) {
				if (sources[at].indexOf(title) < 0) sources[at].push(title);
				continue;
			}

			keys.push(key);
			presets.push(copy);
			played.push(sample);
			sources.push([title]);
			banks.push(sample == null ? DEFAULT : named);

			if (sample == null) own++;
			else hits++;
		}

		Sys.println("  bank          " + StringTools.rpad(title, " ", 20)
			+ StringTools.lpad("" + own, " ", 4) + " presets and "
			+ StringTools.lpad("" + hits, " ", 3) + " hits of its own, " + shared
			+ " already shipped");
	}

	/**
		Writes the default bank and a document for each kit.

		@param folder The folder to write into.
		@param presets The gathered presets.
		@param played What each one plays, or null.
		@param sources Which pieces each one came out of.
		@param banks Which bank each one goes in.
		@return Nought.
	**/
	static function wrote(folder:String, presets:Array<Instrument>, played:Array<Null<Sample>>,
			sources:Array<Array<String>>, banks:Array<String>):Int {
		final named:Array<String> = [];

		for (one in banks) if (named.indexOf(one) < 0) named.push(one);

		for (bank in named) {
			final made:Array<Instrument> = [];
			final held:Array<Null<Sample>> = [];
			final taken:Array<String> = [];

			var bytes = 0;
			var hits = 0;

			for (index in 0...presets.length) {
				if (banks[index] != bank) continue;

				final one = presets[index];

				for (title in sources[index]) one.tags.push(title);

				var called = one.name;
				var at = 2;

				while (taken.indexOf(called) >= 0) {
					called = one.name + " " + at;
					at++;
				}

				one.name = called;
				taken.push(called);

				made.push(one);
				held.push(played[index]);

				final sample = played[index];

				if (sample != null) {
					hits++;
					bytes += sample.length();
				}
			}

			sys.io.File.saveContent(folder + "/" + slug(bank) + Library.SUFFIX,
				Library.written(bank, made, held));

			Sys.println("    " + StringTools.rpad(bank, " ", 20)
				+ StringTools.lpad("" + made.length, " ", 4) + " presets, "
				+ StringTools.lpad("" + hits, " ", 3) + " of them hits over "
				+ StringTools.lpad("" + bytes, " ", 7) + " bytes");
		}

		return 0;
	}

	/**
		@param named A bank name.
		@return What its document is called, in lower case with a hyphen for each space.
	**/
	static function slug(named:String):String {
		var out = "";

		for (index in 0...named.length) {
			final one = named.charAt(index);
			out += one == " " ? "-" : one.toLowerCase();
		}

		return out;
	}

	/**
		@param shipped What already ships.
		@param instrument A preset of the piece's.
		@param sample What it plays, or null.
		@return Whether a shipped preset of the same name for the same part plays the same
			recording, byte for byte. A hit is its recording: two that differ only in a tag or an
			icon are the same hit, and shipping the second one puts a second copy of the bytes in
			the binary for nothing.
	**/
	static function sounded(shipped:Library, instrument:Instrument, sample:Null<Sample>):Bool {
		if (sample == null || sample.length() == 0) return false;

		for (at in 0...shipped.names.length) {
			for (which in 0...shipped.instruments[at].length) {
				final other = shipped.instruments[at][which];
				if (other.name != instrument.name) continue;
				if (!Library.kin(other.kind, instrument.kind)) continue;

				final theirs = shipped.samples[at][which];
				if (theirs == null || theirs.length() != sample.length()) continue;

				var same = true;

				for (byte in 0...sample.length()) {
					if (sample.bytes[byte] == theirs.bytes[byte]) continue;

					same = false;
					break;
				}

				if (same) return true;
			}
		}

		return false;
	}

	/**
		@return The set every piece begins with, as a library.
	**/
	static function starters():Library {
		final out = new Library();
		final held = new Song("starters");

		mdd.song.Shipped.into(held);

		for (index in 0...held.instruments.length) {
			final one = held.instrumentAt(index);
			if (one != null) out.adds(Library.STARTERS, one, null, false);
		}

		return out;
	}
}
