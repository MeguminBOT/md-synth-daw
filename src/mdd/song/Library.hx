package mdd.song;

import mdd.format.Json;
import mdd.format.Tfi;

/**
	The preset banks: what ships inside the binary, and what a reader has put in their
	own presets folder.

	A library is copied into a song, so a song never depends on a bank being installed
	to open. The shipped banks are read once; the folder is read at startup and again
	whenever it may have changed, and every preset saved from the browser is written
	into it, so a preset saved in one piece is offered in every other.
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
		Whether each bank came out of the presets folder rather than the binary. A song
		that already carries a bank of that name is given whatever the folder has gained
		since; a shipped bank it carries is left as it is.
	**/
	public final owned:Array<Bool> = [];

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
	public function reads(said:String, owned:Bool = false, loose:String = ""):Int {
		return taken(said, owned, loose, false);
	}

	/**
		Reads a bank document the application has just written, so each preset in it
		takes the place of one with the same name rather than being passed over.

		@param said The bank as JSON.
		@param loose The bank a document with no name of its own goes into.
		@return How many instruments it carried.
	**/
	public function replaces(said:String, loose:String = ""):Int {
		return taken(said, true, loose, true);
	}

	/**
		@param said The bank as JSON.
		@param owned Whether it came out of the presets folder.
		@param loose The bank a document with no name of its own goes into.
		@param over Whether a preset replaces one of the same name.
		@return How many instruments it added or replaced.
	**/
	function taken(said:String, owned:Bool, loose:String, over:Bool):Int {
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
			} else if (adds(named, instrument, sample, owned)) {
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
		@return False where the bank already had one of that name, or where a preset out of the
			folder makes a sound this library already offers.
	**/
	public function adds(bank:String, instrument:Instrument, sample:Null<Sample>,
			owned:Bool):Bool {
		final at = banked(bank, owned);
		if (holding(at, instrument) >= 0) return false;
		if (owned && sample == null && echoes(instrument)) return false;

		instruments[at].push(instrument);
		samples[at].push(sample);

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
		@param instrument A preset.
		@return Whether this library holds one of that name for that kind of part, which is what
			says it can be given back to a piece that leaves it out.
	**/
	public function knows(instrument:Instrument):Bool {
		for (bank in instruments) {
			for (held in bank) {
				if (held.name == instrument.name && kin(held.kind, instrument.kind)) return true;
			}
		}

		return false;
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
		Copies every bank into a song, with its own instruments and samples, so nothing
		is shared with the library afterwards.

		A shipped bank the song already carries is left as it is. A bank out of the
		presets folder that the song already carries is given each preset it does not
		have a preset of that name for, so what was saved while another piece was open
		reaches this one too.

		The set every piece begins with is the exception, because every piece carries it before
		anything is read: it is built in code so that a new piece has something to play, and what
		ships beside it is added to it rather than passed over.

		A bank made here is the library's rather than the piece's, so a file written afterwards
		leaves it out and the library puts it back at the next opening. One the piece already had
		is left as the piece had it, which is what keeps a bank the reader asked to keep.

		@param song The song to copy into.
		@return How many instruments were added.
	**/
	public function into(song:Song):Int {
		var many = 0;

		for (at in 0...names.length) {
			final carried = carries(song, names[at]);
			if (carried && !owned[at] && names[at] != STARTERS) continue;

			final bank = song.banked(names[at], false);
			final held = instruments[at];

			for (which in 0...held.length) {
				if (carried && offers(song, bank, held[which]) >= 0) continue;

				final made = held[which].copy();
				final sample = samples[at][which];

				if (sample != null) {
					song.sample(sample.copy());
					made.sample = song.samples.length - 1;
				}

				song.instrument(made);

				final index = song.instruments.length - 1;

				song.bank(0).remove(index);
				bank.add(index);

				many++;
			}
		}

		return many;
	}

	/**
		The bank a piece's starting presets sit in, which is where the application puts the set
		every new piece begins with.
	**/
	public static inline final STARTERS = "Default";

	/**
		What a kit is called where nothing else names it.
	**/
	public static inline final KIT = "Kit";

	/**
		@param song The piece.
		@param library The library to ask, which is this one or the starting set.
		@param hits A kit, by index into the piece.
		@return The bank that offers the whole kit, or an empty string where it offers none of it
			or only part of it. A kit is a unit: filing one into a bank that holds a different kit
			puts two hits on the same key, and the one that sounds is whichever comes first.
	**/
	static function whole(song:Song, library:Library, hits:Array<Int>):String {
		var named = "";

		for (index in hits) {
			final held = song.instrumentAt(index);
			if (held == null) continue;

			final want = library.offering(song, held);
			if (want == "") return "";

			if (named == "") named = want;
			else if (named != want) return "";
		}

		return named;
	}

	/**
		Works out what to call a kit no library offers.

		A kit cannot share a bank with anything else, because a drum note picks its hit by note
		out of the bank the rack's converter preset sits in: put a stray hit in there and it
		sounds on whatever key it was recorded at, on a piece that never had it. So the one bank
		a kit may not go in is the one everything the library does not recognise goes in.

		@param song The piece.
		@param held What the file called the bank the kit is in.
		@param named The bank everything else the library does not recognise goes in.
		@return What to call the kit.
	**/
	static function alone(song:Song, held:String, named:String):String {
		if (held != "" && held != named) return held;
		if (song.name != "" && song.name != named) return song.name;

		return KIT;
	}

	/**
		Files every preset a piece carries under the bank it belongs in, which is what a piece read
		from a file needs: `STARTERS` where it is one of the set every piece begins with, one of
		this library's banks where the library offers the same preset, and `named` for the rest,
		which is what the file itself brought. The starting set is asked first, so the bank a piece
		opens with holds what it always holds rather than scattering into the shipped banks that
		some of it also sits in. A preset the bank already holds is left out of every bank
		rather than listed twice, so a project carrying the presets folder twice, as one written
		before the folder had a name of its own does, lists each preset once.

		A kit is the one thing bank membership decides rather than only shows: a converter note
		sounds the hit in the bank the rack's own converter preset sits in, and the roll draws its
		rows from the same bank. The presets in that bank are therefore filed together, wherever
		the rack's own preset belongs, so a kit gathered from several places stays one kit.

		Nothing else moves. No instrument is added, removed or renumbered here, so everything a
		note, a rack or a preset lane names is still what it was.

		@param song The piece.
		@param named The bank for a preset neither this library nor the starting set offers.
		@return How many presets changed bank.
	**/
	public function files(song:Song, named:String):Int {
		final starting = starters();
		final home = song.banked(named, false);
		final hits:Array<Int> = [];

		var kitted = "";

		final rack = song.rack[Part.Dac.index()];
		final at = rack < 0 ? -1 : song.bankOf(rack);

		if (at >= 0 && at < song.banks.length && song.banks[at].holds(rack)) {
			final held = song.instrumentAt(rack);

			if (held != null) {
				for (one in song.banks[at].instruments) hits.push(one);

				kitted = whole(song, starting, hits);
				if (kitted == "") kitted = whole(song, this, hits);
				if (kitted == "") kitted = alone(song, song.banks[at].name, named);
			}
		}

		var moved = 0;

		for (index in 0...song.instruments.length) {
			final held = song.instrumentAt(index);
			if (held == null) continue;

			var want = starting.offering(song, held);
			if (want == "") want = offering(song, held);
			if (want == "") want = named;

			final kit = hits.indexOf(index) >= 0;
			if (kit) want = kitted;

			final bank = want == named ? home : song.banked(want, false);
			var changed = false;

			for (one in song.banks) {
				if (one != bank && one.remove(index)) changed = true;
			}

			final twin = kit ? -1 : twinned(song, bank, held, index);

			if (twin >= 0) {
				if (bank.remove(index)) changed = true;
			} else if (!bank.holds(index)) {
				bank.add(index);
				changed = true;
			}

			if (changed) moved++;
		}

		return moved;
	}

	/**
		@param song The piece the preset belongs to, for the sample a converter preset plays.
		@param instrument A preset.
		@return The name of the bank here that offers the same preset, or an empty string where
			none does.
	**/
	public function offering(song:Song, instrument:Instrument):String {
		for (at in 0...names.length) {
			final which = holding(at, instrument);
			if (which < 0 || !alike(instruments[at][which], instrument)) continue;
			if (!carriesSample(song, instrument, samples[at][which])) continue;

			return names[at];
		}

		return "";
	}

	/**
		@param song A song.
		@param bank One of its banks.
		@param instrument A preset in it, by value.
		@param index That preset, by index into the song.
		@return Another preset already in that bank that is the same one, by index into the song,
			or -1 where the bank holds no other copy of it.
	**/
	static function twinned(song:Song, bank:Bank, instrument:Instrument, index:Int):Int {
		for (at in bank.instruments) {
			if (at == index) continue;

			final held = song.instrumentAt(at);
			if (held == null || !same(held, instrument) || !alike(held, instrument)) continue;
			if (!sameHit(song, held, instrument)) continue;

			return at;
		}

		return -1;
	}

	/**
		A converter preset is only the same preset as another where it plays the same recording.
		`alike` answers on the name, the kind and the patch or envelope alone, which two hits named
		`Kick` in different kits both pass.

		@param song The piece both belong to.
		@param one A preset.
		@param two Another.
		@return Whether they play the same bytes at the same rate, or neither is a converter preset.
	**/
	static function sameHit(song:Song, one:Instrument, two:Instrument):Bool {
		if (!one.kind.sampled() || !two.kind.sampled()) return true;

		return heard(song.sampleAt(one.sample), song.sampleAt(two.sample));
	}

	/**
		@param song The piece the preset belongs to.
		@param instrument A preset.
		@param sample What a bank here has it playing, or null.
		@return Whether the preset plays that recording, or is not a converter preset at all.
	**/
	static function carriesSample(song:Song, instrument:Instrument, sample:Null<Sample>):Bool {
		if (!instrument.kind.sampled()) return true;

		return heard(song.sampleAt(instrument.sample), sample);
	}

	/**
		@param one A recording, or null.
		@param two Another, or null.
		@return Whether both are missing, or both hold the same bytes at the same rate.
	**/
	static function heard(one:Null<Sample>, two:Null<Sample>):Bool {
		if (one == null || two == null) return one == null && two == null;
		if (one.rate != two.rate || one.length() != two.length()) return false;

		for (index in 0...one.length()) {
			if (one.bytes[index] != two.bytes[index]) return false;
		}

		return true;
	}

	/**
		@return A library of the presets every new piece begins with, in one bank named `STARTERS`.
	**/
	static function starters():Library {
		final out = new Library();
		final song = new Song("starters");

		mdd.song.Shipped.into(song);

		for (index in 0...song.instruments.length) {
			final held = song.instrumentAt(index);
			if (held != null) out.adds(STARTERS, held, null, false);
		}

		return out;
	}

	/**
		@param song A song.
		@param name A bank's name.
		@return Whether the song has a bank of that name with anything in it.
	**/
	static function carries(song:Song, name:String):Bool {
		for (bank in song.banks) {
			if (bank.name == name && bank.instruments.length > 0) return true;
		}

		return false;
	}

	/**
		@param song A song.
		@param bank One of its banks.
		@param instrument A preset.
		@return The song's instrument in that bank with the preset's name, for the same
			kind of part, by index into the song, or -1 where there is none.
	**/
	static function offers(song:Song, bank:Bank, instrument:Instrument):Int {
		for (index in bank.instruments) {
			final held = song.instrumentAt(index);
			if (held != null && same(held, instrument)) return index;
		}

		return -1;
	}

	/**
		Takes every bank that came out of the presets folder out of the library, so the
		folder can be read again from nothing.

		@return A library holding what was taken out, which `prunes` compares against.
	**/
	public function sheds():Library {
		final out = new Library();
		var at = 0;

		while (at < names.length) {
			if (!owned[at]) {
				at++;
				continue;
			}

			out.names.push(names[at]);
			out.instruments.push(instruments[at]);
			out.samples.push(samples[at]);
			out.owned.push(true);

			names.splice(at, 1);
			instruments.splice(at, 1);
			samples.splice(at, 1);
			owned.splice(at, 1);
		}

		return out;
	}

	/**
		Takes out of a song's banks each preset the presets folder held before it was
		read again and no longer holds in that bank, so a preset moved into a subfolder
		or deleted in the file manager leaves the bank it was in. Only a preset still
		exactly as the folder had it is taken out: one edited in the song, or one the
		song brought with it, stays. Nothing leaves the song itself, so whatever plays
		it still does.

		@param song The song.
		@param before What `sheds` took out before the folder was read again.
		@return How many presets left a bank.
	**/
	public function prunes(song:Song, before:Library):Int {
		var many = 0;

		for (at in 0...before.names.length) {
			final name = before.names[at];
			final now = names.indexOf(name);

			for (bank in song.banks) {
				if (bank.name != name) continue;

				for (instrument in before.instruments[at]) {
					if (now >= 0 && holding(now, instrument) >= 0) continue;

					final index = offers(song, bank, instrument);
					if (index < 0) continue;

					final held = song.instrumentAt(index);
					if (held == null || !alike(held, instrument)) continue;

					bank.remove(index);
					many++;
				}
			}
		}

		return many;
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
		@return How many presets it carried.
	**/
	public function holds(bytes:Null<haxe.io.Bytes>, owned:Bool = false, loose:String = "",
			over:Bool = false):Int {
		final held = mdd.format.Preset.read(bytes);
		if (held == null) return 0;

		final named = held.name == "" ? loose : held.name;
		if (named == "") return 0;

		var many = 0;

		for (index in 0...held.presets.length) {
			if (over) {
				keeps(named, held.presets[index], held.samples[index]);
				many++;
			} else if (adds(named, held.presets[index], held.samples[index], owned)) {
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
	static inline final CACHED = "MDL1";

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

				for (index in 0...held.presets.length) {
					holding.push(held.presets[index]);
					playing.push(held.samples[index]);

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

			for (index in 0...held.length) {
				if (adds(other.names[at], held[index], sampled[index], other.owned[at])) many++;
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

				if (StringTools.endsWith(lower, RECORDS) || StringTools.endsWith(lower, BANK)) {
					many += holds(sys.io.File.getBytes(path), true, loose);
				} else if (StringTools.endsWith(lower, SUFFIX)) {
					many += reads(sys.io.File.getContent(path), true, loose);
				} else if (StringTools.endsWith(lower, PATCH)) {
					final patch = Tfi.read(sys.io.File.getBytes(path));
					if (patch == null) continue;

					final one = new Instrument(stem(name), Part.Fm1);

					one.patch = patch;
					one.icon = mdd.Icon.NAMES.indexOf("synthesizer");

					if (adds(loose, one, null, true)) many++;
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
