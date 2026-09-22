package mdd.song;

import mdd.format.Json;
import mdd.format.Tfi;

/**
	The preset banks: what ships inside the binary, and what a reader has put in their
	own presets folder.

	A library is what is installed, and a piece is never copied from it wholesale: the browser
	offers what the library holds, and a preset loaded into a channel is copied into the piece
	then, so a piece carries what it plays and nothing else. The shipped banks are read once; the
	folder is read at startup and again whenever it may have changed, and every preset saved from
	the browser is written into it, so a preset saved in one piece is offered in every other.
**/
@:unreflective
final class Library {
	/**
		The name of each bank.
	**/
	public final names:Array<String> = [];

	/**
		The instruments in each bank.
	**/
	public final instruments:Array<Array<Instrument>> = [];

	/**
		The sample each instrument needs, where it needs one.
	**/
	public final samples:Array<Array<Null<Sample>>> = [];

	/**
		Whether each bank came out of the presets folder rather than the binary, which is what
		reading the folder again replaces.
	**/
	public final owned:Array<Bool> = [];

	/**
		When the file each preset was read from was last written, in seconds since 1970, by the
		same index as the instruments, or nought for a preset that ships or was read back from the
		cache. It is what dates a preset the first time it is seen.
	**/
	public final times:Array<Array<Float>> = [];

	public function new() {}

	/**
		What a bank resource is called inside the binary.
	**/
	public static inline final PREFIX = "bank.";

	/**
		Reads every bank compiled into the binary.

		@return The library those banks make up.
	**/
	public static function embedded():Library {
		final out = new Library();
		final held:Array<String> = [];

		for (name in haxe.Resource.listNames()) {
			if (name.length > PREFIX.length && name.substr(0, PREFIX.length) == PREFIX) {
				held.push(name);
			}
		}

		held.sort(function(one:String, two:String):Int return one < two ? -1 : 1);

		for (name in held) out.holds(haxe.Resource.getBytes(name));

		return out;
	}

	/**
		Reads one bank document and adds it. A bank of the same name already here takes
		the presets it does not have yet, and keeps its own where both have one.

		@param said The bank as JSON.
		@param owned Whether it came out of the presets folder.
		@param loose The bank a document with no name of its own goes into, which is how
			a single saved preset is written. Empty to pass such a document over.
		@return How many instruments it added.
	**/
	public function reads(said:String, owned:Bool = false, loose:String = "", time:Float = 0):Int {
		return taken(said, owned, loose, false, time);
	}

	/**
		Reads a bank document the application has just written, so each preset in it
		takes the place of one with the same name rather than being passed over.

		@param said The bank as JSON.
		@param loose The bank a document with no name of its own goes into.
		@return How many instruments it carried.
	**/
	public function replaces(said:String, loose:String = ""):Int {
		return taken(said, true, loose, true, 0);
	}

	/**
		@param said The bank as JSON.
		@param owned Whether it came out of the presets folder.
		@param loose The bank a document with no name of its own goes into.
		@param over Whether a preset replaces one of the same name.
		@param time When the document was last written, in seconds since 1970, or nought.
		@return How many instruments it added or replaced.
	**/
	function taken(said:String, owned:Bool, loose:String, over:Bool, time:Float):Int {
		final node = Json.parse(said);
		if (node == null) return 0;

		final named = node.get("name").saying(loose);
		if (named == "") return 0;

		final presets = node.get("presets");
		var many = 0;

		for (index in 0...presets.length()) {
			final one = presets.at(index);
			final instrument = preset(one);
			if (instrument == null) continue;

			final sample = instrument.kind.sampled() ? sampled(instrument.name,
				one.get("pcm").saying(""), one.get("rate").whole(8000),
				one.get("root").whole(60)) : null;

			if (instrument.kind.sampled() && sample == null) continue;
			if (sample != null) sample.loop = one.get("loop").whole(-1);

			instrument.identifies(sample);

			if (over) {
				keeps(named, instrument, sample);
				many++;
			} else if (adds(named, instrument, sample, owned, time)) {
				many++;
			}
		}

		return many;
	}

	/**
		@param bytes A preset file or a bank file out of the presets folder.
		@return Which family of part every preset in it is for, as `Part.family` names it, or an
			empty string where it will not read, carries no preset or carries more than one
			family. A file that answers one is a file that belongs in that family's folder.
	**/
	public static function familyOf(bytes:Null<haxe.io.Bytes>):String {
		final held = mdd.format.Preset.read(bytes);
		if (held == null || held.presets.length == 0) return "";

		final out = held.presets[0].kind.family();

		for (one in held.presets) if (one.kind.family() != out) return "";

		return out;
	}

	/**
		@param said A document out of the presets folder.
		@return Which family of part every preset in it is for, as `Part.family` names it, or an
			empty string where it carries no preset or carries more than one family. A file that
			answers one is a file that belongs in that family's folder. A document naming a bank
			of its own answers the same way, because it is that bank wherever it sits.
	**/
	public static function familyIn(said:String):String {
		final node = mdd.format.Json.parse(said);
		if (node == null) return "";

		final presets = node.get("presets");
		var family = "";

		for (index in 0...presets.length()) {
			final held = preset(presets.at(index));
			if (held == null) return "";
			if (family != "" && family != held.kind.family()) return "";

			family = held.kind.family();
		}

		return family;
	}

	/**
		Reads one preset out of a bank document, in either layout: the one the shipped
		banks are written in, or a whole instrument as a project carries it.

		@param one The preset.
		@return The instrument, or null where it carries nothing that plays.
	**/
	static function preset(one:mdd.format.Node):Null<Instrument> {
		final pcm = one.get("pcm").saying("");

		if (one.has("instrument")) {
			final made = mdd.format.Project.readInstrument(one.get("instrument"));
			made.sample = -1;

			if (made.kind.sampled() && pcm == "") return null;
			if (made.kind.fm() && made.patch == null) return null;
			if ((made.kind.square() || made.kind.noise()) && made.envelope == null) return null;

			return made;
		}

		final noise = one.get("noise");
		final drawn = noise.get("steps");
		final beats = drawn.length();

		final patch = pcm == "" && beats == 0 ? patched(one.get("tfi").saying("")) : null;
		if (patch == null && pcm == "" && beats == 0) return null;

		final where = beats > 0 ? Part.Noise : (patch == null ? Part.Dac : Part.Fm1);
		final instrument = new Instrument(one.get("name").saying("patch"), where);

		if (patch != null) instrument.patch = patch;

		final envelope = instrument.envelope;

		if (beats > 0 && envelope != null) {
			for (step in 0...beats) envelope.steps.push(drawn.at(step).whole(15));

			envelope.turns(Envelope.NOISE, noise.get("mode").whole(7));
			envelope.turns(Envelope.SPEED, noise.get("speed").whole(1));
			envelope.turns(Envelope.LOOP, noise.get("loop").whole(-1));
		}

		instrument.icon = mdd.Icon.NAMES.indexOf(one.get("icon").saying(""));

		final tags = one.get("tags");
		for (at in 0...tags.length()) {
			final tag = tags.at(at).saying("");
			if (tag != "") instrument.tags.push(tag);
		}

		return instrument;
	}

	/**
		Finds a bank by name, making an empty one where there is none.

		@param name What it is called.
		@param owned Whether it came out of the presets folder.
		@return Where it is.
	**/
	function banked(name:String, owned:Bool):Int {
		var at = names.indexOf(name);

		if (at < 0) {
			names.push(name);
			instruments.push([]);
			samples.push([]);
			times.push([]);
			this.owned.push(owned);

			at = names.length - 1;
		} else if (owned) {
			this.owned[at] = true;
		}

		return at;
	}

	/**
		Puts a preset into a bank, unless the bank already has one of the same name for
		the same kind of part.

		A patch or an envelope out of the presets folder is put in only where nothing here already
		makes that sound, whatever either is called. Lifting a piece's patches used to write every
		preset the piece carried into the folder, and a piece carried the whole library, so a
		folder fills up with the shipped banks under names like `Bass 7 2` that say nothing about
		what they play. A shipped bank is added as it is, because the same patch turning up in two
		soundtracks is what those banks are for.

		A converter preset is never held back that way. A kit is picked by note out of one bank,
		so a hit left out because another bank has the same recording is a key that stops
		sounding.

		@param bank The bank's name. It is made where there is none.
		@param instrument The preset. The library keeps it rather than a copy.
		@param sample The sample it plays, or null.
		@param owned Whether it came out of the presets folder.
		@param time When its file was last written, in seconds since 1970, or nought.
		@return False where the bank already had one of that name, or where a preset out of the
			folder makes a sound this library already offers.
	**/
	public function adds(bank:String, instrument:Instrument, sample:Null<Sample>,
			owned:Bool, time:Float = 0):Bool {
		final at = banked(bank, owned);
		if (holding(at, instrument) >= 0) return false;
		if (owned && sample == null && echoes(instrument)) return false;

		instruments[at].push(instrument);
		samples[at].push(sample);
		times[at].push(time);

		return true;
	}

	/**
		@param instrument A preset that plays no recording, about to be put in.
		@return Whether this library already offers that sound, in any bank.
	**/
	function echoes(instrument:Instrument):Bool {
		for (at in 0...names.length) {
			final held = instruments[at];

			for (which in 0...held.length) {
				if (samples[at][which] == null && sounds(held[which], instrument)) return true;
			}
		}

		return false;
	}

	/**
		Puts a preset into a bank the presets folder owns, taking the place of one with
		the same name for the same kind of part.

		@param bank The bank's name. It is made where there is none.
		@param instrument The preset. The library keeps it rather than a copy.
		@param sample The sample it plays, or null.
	**/
	public function keeps(bank:String, instrument:Instrument, sample:Null<Sample>):Void {
		final at = banked(bank, true);
		final held = called(at, instrument);

		if (held < 0) {
			instruments[at].push(instrument);
			samples[at].push(sample);
			times[at].push(0);
			return;
		}

		instruments[at][held] = instrument;
		samples[at][held] = sample;
	}

	/**
		@param at A bank, by position.
		@param instrument A preset.
		@return Where the bank holds one of the same name for the same kind of part, or
			-1 where it holds none.
	**/
	function holding(at:Int, instrument:Instrument):Int {
		final held = instruments[at];

		for (which in 0...held.length) if (same(held[which], instrument)) return which;

		return -1;
	}

	/**
		@param at Which bank.
		@param instrument A preset.
		@return Where a preset of that name for that kind of part sits in the bank, or -1. This is
			what a file stands for rather than what a preset is: a file keeps its name while what
			is written into it changes, so a save over one takes the place of what it held.
	**/
	function called(at:Int, instrument:Instrument):Int {
		final held = instruments[at];

		for (which in 0...held.length) {
			if (held[which].name == instrument.name && kin(held[which].kind, instrument.kind)) {
				return which;
			}
		}

		return -1;
	}

	/**
		@param one A preset.
		@param two Another.
		@return Whether they are the same preset rather than two that read alike: their identities
			where both carry one, and the name and the kind of part otherwise, which is all a
			preset written before identities carries.
	**/
	public static function same(one:Instrument, two:Instrument):Bool {
		if (one.id != "" && two.id != "") return one.id == two.id;

		return one.name == two.name && kin(one.kind, two.kind);
	}

	/**
		@param one A part.
		@param two Another.
		@return Whether an instrument for one plays on the other.
	**/
	public static function kin(one:Part, two:Part):Bool {
		if (one.fm()) return two.fm();
		if (one.square()) return two.square();
		if (one.noise()) return two.noise();

		return one.sampled() && two.sampled();
	}

	/**
		@param one An instrument.
		@param two Another.
		@return Whether they are the same preset: the same name, for the same kind of
			part, with the same patch or envelope. Samples are not compared.
	**/
	public static function alike(one:Instrument, two:Instrument):Bool {
		if (!same(one, two) || one.name != two.name) return false;

		return sounds(one, two);
	}

	/**
		@param one A preset.
		@param two Another.
		@return Whether the two make the same sound: the same kind of part, the same patch, the
			same envelope. What either is called is no part of it, because a reader's folder fills
			with one patch under several names and the browser should offer it once. A recording
			is compared by `carriesSample` rather than here.
	**/
	public static function sounds(one:Instrument, two:Instrument):Bool {
		if (!kin(one.kind, two.kind)) return false;

		final patch = one.patch;
		final other = two.patch;

		if ((patch == null) != (other == null)) return false;

		if (patch != null && other != null) {
			if (patch.algorithm != other.algorithm || patch.feedback != other.feedback
					|| patch.ams != other.ams || patch.pms != other.pms) {
				return false;
			}

			for (slot in 0...Patch.SLOTS) {
				if (patch.tremolo[slot] != other.tremolo[slot]) return false;

				for (row in 0...Patch.ROWS) {
					if (patch.reads(slot, row) != other.reads(slot, row)) return false;
				}
			}
		}

		final envelope = one.envelope;
		final shape = two.envelope;

		if ((envelope == null) != (shape == null)) return false;

		if (envelope != null && shape != null) {
			if (envelope.loop != shape.loop || envelope.speed != shape.speed
					|| envelope.noise != shape.noise
					|| envelope.steps.length != shape.steps.length) {
				return false;
			}

			for (step in 0...envelope.steps.length) {
				if (envelope.steps[step] != shape.steps[step]) return false;
			}
		}

		return true;
	}

	/**
		The bank of presets the application is built with, which is the one bank a reader cannot
		delete and the one a new piece takes its channels from.
	**/
	public static inline final STARTERS = "Default";

	/**
		@param instrument A preset, its identity worked out.
		@return The name of the first bank here holding the same preset, or an empty string where
			none does.
	**/
	public function offering(instrument:Instrument):String {
		if (instrument.id == "") return "";

		for (at in 0...names.length) {
			for (held in instruments[at]) if (held.id == instrument.id) return names[at];
		}

		return "";
	}

	/**
		Takes every bank that came out of the presets folder out of the library, so the folder can
		be read again from nothing. What ships is left.
	**/
	public function forgets():Void {
		var at = 0;

		while (at < names.length) {
			if (!owned[at]) {
				at++;
				continue;
			}

			names.splice(at, 1);
			instruments.splice(at, 1);
			samples.splice(at, 1);
			times.splice(at, 1);
			owned.splice(at, 1);
		}
	}

	/**
		What a bank document is called on disk.
	**/
	public static inline final SUFFIX = ".json";

	/**
		What a patch file is called on disk.
	**/
	public static inline final PATCH = ".tfi";

	/**
		What a preset file is called on disk, which is what this application writes.
	**/
	public static inline final RECORDS = mdd.format.Preset.SUFFIX;

	/**
		What a bank of presets is called on disk, which is the same records naming a bank.
	**/
	public static inline final BANK = mdd.format.Preset.BANK;

	/**
		Takes a bank out of a preset file.

		@param bytes The file.
		@param owned Whether it came out of the presets folder.
		@param loose The bank a file naming none goes into.
		@param over Whether a preset takes the place of one of the same name rather than being
			passed over, which is right for a file the application has just written and wrong for
			one it is reading for the first time.
		@param time When the file was last written, in seconds since 1970, or nought.
		@return How many presets it carried.
	**/
	public function holds(bytes:Null<haxe.io.Bytes>, owned:Bool = false, loose:String = "",
			over:Bool = false, time:Float = 0):Int {
		final held = mdd.format.Preset.read(bytes);
		if (held == null) return 0;

		final named = held.name == "" ? loose : held.name;
		if (named == "") return 0;

		var many = 0;

		for (index in 0...held.presets.length) {
			if (over) {
				keeps(named, held.presets[index], held.samples[index]);
				many++;
			} else if (adds(named, held.presets[index], held.samples[index], owned, time)) {
				many++;
			}
		}

		return many;
	}

	/**
		How deep into subfolders a presets folder is read, below the folder its family stands in.
	**/
	public static inline final DEPTH = 4;

	/**
		The folders a presets folder is divided into, one for each family of part, as
		`Part.family` names them. They are not banks themselves: what a reader puts inside one is.
	**/
	public static final FAMILIES:Array<String> = ["FM", "PSG", "NOISE", "DAC"];

	/**
		@param name A folder's name.
		@return Whether it stands for a family of part rather than for a bank of its own.
	**/
	public static function familied(name:String):Bool {
		final lower = name.toLowerCase();

		for (family in FAMILIES) if (family.toLowerCase() == lower) return true;

		return false;
	}

	/**
		Reads a folder of bank documents and loose presets, so a reader's own presets
		load beside the shipped ones rather than replacing them.

		A bank document with a name of its own is that bank wherever it sits. A loose
		preset, which is a patch file or a document with no name, goes into the bank its
		folder stands for: the one named `saved` at the top, and one named for the
		subfolder below it, so a subfolder made in the file manager is a bank.

		The four folders a presets folder is divided into by family of part, which `FAMILIES`
		names, stand for no bank of their own: what is loose in one is saved, and a folder inside
		one is a bank the same way a folder at the top is.

		@param where The folder to read.
		@param saved The bank loose presets at the top of it go into.
		@return How many instruments were read.
	**/
	public function within(where:String, saved:String):Int {
		return gathered(where, saved, 0);
	}

	/**
		What a cache of a read folder opens with.
	**/
	static inline final CACHED = "MDL2";

	/**
		Writes what this library holds as one file, with the listing of the folder it was read
		from, so the next start reads one file rather than every file in a folder.

		The cache is what was read rather than what is on disk: it is written after a folder read
		and it is only read back while the listing still matches, so a file added, removed or
		written to in the file manager throws it away. It holds no identity and no star, because
		both are worked out from what a preset holds.

		@param where The file to write.
		@param stamp The folder listing it was read from.
		@return Whether it was written.
	**/
	public function caches(where:String, stamp:String):Bool {
		final out = new haxe.io.BytesOutput();

		out.writeString(CACHED);
		out.writeInt32(stamp.length);
		out.writeString(stamp);
		out.writeInt32(names.length);

		for (at in 0...names.length) {
			final bytes = mdd.format.Preset.write(names[at], instruments[at], samples[at]);

			out.writeByte(owned[at] ? 1 : 0);
			out.writeInt32(bytes.length);
			out.write(bytes);
		}

		try {
			sys.io.File.saveBytes(where, out.getBytes());
		} catch (e:Dynamic) {
			return false;
		}

		return true;
	}

	/**
		Reads a cache back into a library holding nothing.

		Nothing is compared against what is already here: a cache is written from a library that
		already kept one of each, and it is only read into an empty one, so the duplicate check a
		folder read pays for every preset against every preset already in its bank is work with a
		known answer.

		@param where The file to read.
		@param stamp What the folder lists now.
		@return How many presets it carried, or -1 where there is no cache, where it will not read
			or where the folder has changed under it, all of which mean the folder has to be read.
	**/
	public function cached(where:String, stamp:String):Int {
		if (where == "" || !sys.FileSystem.exists(where)) return -1;

		try {
			final from = new haxe.io.BytesInput(sys.io.File.getBytes(where));

			if (from.readString(CACHED.length) != CACHED) return -1;

			final length = from.readInt32();
			if (length != stamp.length || from.readString(length) != stamp) return -1;

			final banks = from.readInt32();
			var many = 0;

			for (at in 0...banks) {
				final kept = from.readByte() != 0;
				final held = mdd.format.Preset.read(from.read(from.readInt32()));

				if (held == null || held.name == "") return -1;

				final into = banked(held.name, kept);
				final holding = instruments[into];
				final playing = samples[into];
				final dated = times[into];

				for (index in 0...held.presets.length) {
					holding.push(held.presets[index]);
					playing.push(held.samples[index]);
					dated.push(0);

					many++;
				}
			}

			return many;
		} catch (e:Dynamic) {}

		return -1;
	}

	/**
		Puts everything another library holds into this one, which is what a folder read through a
		library of its own leaves to do.

		@param other The library to take from. It keeps nothing back: this library holds the same
			presets rather than copies of them.
		@return How many presets were added.
	**/
	public function takes(other:Library):Int {
		var many = 0;

		for (at in 0...other.names.length) {
			final held = other.instruments[at];
			final sampled = other.samples[at];
			final dated = other.times[at];

			for (index in 0...held.length) {
				if (adds(other.names[at], held[index], sampled[index], other.owned[at], dated[index])) many++;
			}
		}

		return many;
	}

	/**
		@param where The folder to read.
		@param loose The bank loose presets in it go into.
		@param depth How many folders down from the top it is.
		@return How many instruments were read.
	**/
	function gathered(where:String, loose:String, depth:Int):Int {
		if (where == "" || !sys.FileSystem.exists(where)) return 0;
		if (!sys.FileSystem.isDirectory(where)) return 0;

		final held = sys.FileSystem.readDirectory(where);
		held.sort(function(one:String, two:String):Int return byStem(one, two));

		var many = 0;
		final below:Array<String> = [];

		for (name in held) {
			final path = where + "/" + name;

			try {
				if (sys.FileSystem.isDirectory(path)) {
					below.push(name);
					continue;
				}

				final lower = name.toLowerCase();
				final time = sys.FileSystem.stat(path).mtime.getTime() / 1000;

				if (StringTools.endsWith(lower, RECORDS) || StringTools.endsWith(lower, BANK)) {
					many += holds(sys.io.File.getBytes(path), true, loose, false, time);
				} else if (StringTools.endsWith(lower, SUFFIX)) {
					many += reads(sys.io.File.getContent(path), true, loose, time);
				} else if (StringTools.endsWith(lower, PATCH)) {
					final patch = Tfi.read(sys.io.File.getBytes(path));
					if (patch == null) continue;

					final one = new Instrument(stem(name), Part.Fm1);

					one.patch = patch;
					one.icon = mdd.Icon.NAMES.indexOf("synthesizer");

					if (adds(loose, one, null, true, time)) many++;
				}
			} catch (e:Dynamic) {}
		}

		if (depth >= DEPTH) return many;

		for (name in below) {
			if (StringTools.startsWith(name, ".")) continue;

			final family = depth == 0 && familied(name);
			final into = family ? loose : (depth == 0 ? name : loose + " / " + name);

			many += gathered(where + "/" + name, into, family ? 0 : depth + 1);
		}

		return many;
	}

	/**
		Orders two file names by what they are called rather than by the bytes of the name, so
		`Bass 7` is read before `Bass 7 2`. A space sorts before a dot, so the plain name comes
		last of its family otherwise, and where several files hold the same patch the one that
		arrives first is the one whose name is kept.

		@param one A file name.
		@param two Another.
		@return Which comes first.
	**/
	static function byStem(one:String, two:String):Int {
		final first = stem(one);
		final second = stem(two);

		if (first != second) return first < second ? -1 : 1;

		return one < two ? -1 : (one > two ? 1 : 0);
	}

	/**
		@param name A file name.
		@return It without its suffix.
	**/
	static function stem(name:String):String {
		final dot = name.lastIndexOf(".");
		return dot > 0 ? name.substring(0, dot) : name;
	}

	/**
		Reads a sample out of a bank document.

		@param named What to call it.
		@param said The bytes, base64 encoded.
		@param rate The rate they were written at.
		@param root The MIDI note it sounds at that rate.
		@return The sample, or null where the text was not readable.
	**/
	public static function sampled(named:String, said:String, rate:Int, root:Int):Null<Sample> {
		if (said == "") return null;

		try {
			final bytes = haxe.crypto.Base64.decode(said);
			if (bytes.length < 16) return null;

			final held = new haxe.ds.Vector<Int>(bytes.length);
			for (at in 0...bytes.length) held[at] = bytes.get(at);

			final out = new Sample(named, rate < 1 ? 8000 : rate, root);
			out.hold(held);

			return out;
		} catch (e:Dynamic) {
			return null;
		}
	}

	/**
		Writes a bank document, in the layout `reads` takes back.

		Only sampled instruments are written for now, because that is what a kit is and
		what nothing else here could produce: the shipped banks were all written by
		programs outside the application.

		@param named What the bank is called.
		@param made The instruments, in the order they should appear.
		@param held The sample each one plays, in the same order. An entry with no
			sample is passed over.
		@return The document.
	**/
	/**
		@param one A preset.
		@return A copy of it that names no recording and no preset it came from, which is what a
			bank document holds: a document is read into whichever piece opens it, and an index
			into another piece means nothing there.
	**/
	static function plainly(one:Instrument):Instrument {
		final out = one.copy();

		out.sample = -1;
		out.from = "";

		return out;
	}

	/**
		Writes a bank document, in the layout `reads` takes back.

		A preset that plays a recording is written the way the shipped banks are, with the
		recording beside it. One that does not is written whole, patch, envelope and all, which is
		the other layout `reads` takes and the only one that can carry a patch.

		@param named What the bank is called.
		@param made The instruments, in the order they should appear.
		@param held The sample each one plays, in the same order, or null where it plays none.
		@return The document.
	**/
	public static function written(named:String, made:Array<Instrument>,
			held:Array<Null<Sample>>):String {
		final out = new mdd.format.Json();

		out.open();
		out.key("name");
		out.text(named);
		out.key("presets");
		out.list();

		for (index in 0...made.length) {
			final sample = index < held.length ? held[index] : null;
			final one = made[index];

			if (sample == null || sample.length() == 0) {
				out.open();
				out.key("instrument");
				mdd.format.Project.wroteInstrument(out, plainly(one));
				out.close();

				continue;
			}

			out.open();

			out.key("name");
			out.text(one.name);

			if (one.icon >= 0 && one.icon < mdd.Icon.NAMES.length) {
				out.key("icon");
				out.text(mdd.Icon.NAMES[one.icon]);
			}

			out.key("tags");
			out.list();
			for (tag in one.tags) out.text(tag);
			out.ends();

			out.key("rate");
			out.whole(sample.rate);

			out.key("root");
			out.whole(sample.root);

			out.key("pcm");
			out.text(coded(sample));

			out.close();
		}

		out.ends();
		out.close();

		return out.toString();
	}

	/**
		Writes one preset as a document of its own with no bank name, which is how the
		browser saves a preset into the presets folder: the folder the file sits in says
		which bank it belongs to. It carries the whole instrument, in the layout a project
		writes, so nothing a patch or an envelope holds is lost on the way.

		@param instrument The preset.
		@param sample The sample it plays, or null.
		@return The document.
	**/
	public static function saved(instrument:Instrument, sample:Null<Sample>):String {
		final plain = instrument.copy();
		plain.sample = -1;

		final out = new mdd.format.Json();

		out.open();
		out.key("presets");
		out.list();
		out.open();

		out.key("instrument");
		mdd.format.Project.wroteInstrument(out, plain);

		if (sample != null && sample.length() > 0) {
			out.key("rate");
			out.whole(sample.rate);

			out.key("root");
			out.whole(sample.root);

			out.key("loop");
			out.whole(sample.loop);

			out.key("pcm");
			out.text(coded(sample));
		}

		out.close();
		out.ends();
		out.close();

		return out.toString();
	}

	/**
		@param sample A sample.
		@return Its bytes as base64, which is how a bank document carries them.
	**/
	static function coded(sample:Sample):String {
		final bytes = haxe.io.Bytes.alloc(sample.length());
		for (at in 0...sample.length()) bytes.set(at, sample.bytes[at] & 0xFF);

		return haxe.crypto.Base64.encode(bytes);
	}

	/**
		Reads a patch out of a bank document, in the same layout a TFI file uses.

		@param said The patch as hexadecimal.
		@return The patch, or null where the text was not readable.
	**/
	public static function patched(said:String):Null<Patch> {
		if (said.length < Tfi.BYTES * 2) return null;

		final out = haxe.io.Bytes.alloc(Tfi.BYTES);

		for (at in 0...Tfi.BYTES) {
			out.set(at, digit(said, at * 2) * 16 + digit(said, at * 2 + 1));
		}

		return Tfi.read(out);
	}

	/**
		@param said A string of hexadecimal.
		@param at Which character.
		@return Its value, or -1 where it is not a hexadecimal digit.
	**/
	static function digit(said:String, at:Int):Int {
		final code = said.charCodeAt(at);
		if (code == null) return 0;

		if (code >= 48 && code <= 57) return code - 48;
		if (code >= 97 && code <= 102) return code - 87;
		if (code >= 65 && code <= 70) return code - 55;

		return 0;
	}

	/**
		@return How many instruments the whole library holds.
	**/
	public function count():Int {
		var many = 0;
		for (held in instruments) many += held.length;

		return many;
	}
}
