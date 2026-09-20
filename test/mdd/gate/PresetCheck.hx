package mdd.gate;

import mdd.song.Envelope;
import mdd.song.Instrument;
import mdd.song.Library;
import mdd.song.Part;
import mdd.song.Sample;
import mdd.song.Song;

@:unreflective

/**
	A preset saved in one piece has to be offered in every other, and the presets folder has to be
	what the browser shows.

	Each kind of preset is written the way the browser saves one and read back through the library,
	and nothing a patch or an envelope holds may be lost on the way. A piece that already carries
	the saved bank is given what was saved after it, once. A folder with subfolders reads as one
	bank per subfolder, and a preset moved into a subfolder in the file manager leaves the bank it
	was in, while one edited in the piece stays.
**/
class PresetCheck {
	static var failed:Int = 0;
	static var ran:Int = 0;

	static inline final SAVED = "Saved presets";

	/**
		How many times a read is timed, the best of which is what is reported.
	**/
	static inline final ROUNDS = 7;

	/**
		What the bank of presets a piece was read from is called, in the reader's language. The
		application passes the translation; this is what it reads in English.
	**/
	static inline final FROM_FILE = "From Project File";

	/**
		@param args The gate's arguments, unused.
		@return Nought where every case held.
	**/
	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  presets");

		carried();
		reached();
		shipped();
		filed();
		identified();
		recorded(Gate.root);
		carriedOver(Gate.root);
		loaded();
		converted();
		starred();

		final where = Gate.root + "/export/gate/presets";
		mdd.host.Paths.clear(where);
		mdd.host.Paths.make(where);

		folded(where);
		moved(where);
		written(where);
		poured(where);
		raised(where);
		keptBack(where);
		familied(where);
		sortedIn(where);

		mdd.host.Paths.clear(where);

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");
		Sys.println(failed == 0 ? "    passed" : "    failed");

		return failed == 0 ? 0 : 1;
	}

	/**
		Every kind of preset survives being saved and read back.
	**/
	static function carried():Void {
		final fm = patched("Glass Lead");
		final square = enveloped("Pluck", Part.Psg1);
		final noise = enveloped("Hat", Part.Noise);
		final hit = new Instrument("Kick", Part.Dac);
		final sample = sampled("Kick");

		hit.icon = mdd.Icon.NAMES.indexOf("kick");
		hit.tags.push("Drums");

		final made = [fm, square, noise, hit];
		final held:Array<Null<Sample>> = [null, null, null, sample];

		for (which in 0...made.length) {
			final one = made[which];
			final back = new Library();
			final many = back.reads(Library.saved(one, held[which]), true, SAVED);

			final landed = many == 1 && back.names.length == 1 && back.names[0] == SAVED;
			final same = landed && Library.alike(back.instruments[0][0], one);
			final kept = landed && back.instruments[0][0].icon == one.icon
				&& back.instruments[0][0].tags.join(",") == one.tags.join(",");

			var bytes = true;

			if (landed && held[which] != null) {
				final came = back.samples[0][0];
				final went = held[which];

				bytes = came != null && went != null && came.length() == went.length()
					&& came.rate == went.rate && came.root == went.root && came.loop == went.loop;

				if (bytes && came != null && went != null) {
					for (at in 0...went.length()) if (came.bytes[at] != went.bytes[at]) bytes = false;
				}
			}

			says("a saved " + one.kind.family() + " preset reads back", same && kept && bytes,
				many + " read into '" + (back.names.length == 0 ? "" : back.names[0]) + "'"
				+ (same ? "" : ", not alike") + (kept ? "" : ", icon or tags lost")
				+ (bytes ? "" : ", sample differs"));
		}

		final plain = new Library();
		plain.reads(Library.saved(fm, null), true, SAVED);

		final lfo = plain.instruments.length == 1 && plain.instruments[0][0].patch != null
			&& plain.instruments[0][0].patch.ams == 2 && plain.instruments[0][0].patch.pms == 5
			&& plain.instruments[0][0].patch.tremolo[1];

		says("a saved patch keeps its LFO depths", lfo, lfo ? "ams 2, pms 5, AM on op 2"
			: "lost on the way");
	}

	/**
		A piece opened after a preset was saved is offered it, and a second opening does not
		offer it twice.
	**/
	static function reached():Void {
		final library = new Library();
		library.reads(Library.saved(patched("Old Bass"), null), true, SAVED);

		final older = new Song();
		library.into(older);

		library.keeps(SAVED, patched("New Lead"), null);

		final first = library.into(older);
		final second = library.into(older);

		final bank = older.banked(SAVED);
		final names:Array<String> = [];

		for (index in bank.instruments) {
			final held = older.instrumentAt(index);
			if (held != null) names.push(held.name);
		}

		says("a piece opened later is offered it", first == 1 && second == 0
			&& names.join(",") == "Old Bass,New Lead",
			first + " added, then " + second + ", bank holds " + names.join(", "));
	}

	/**
		A shipped bank a piece carries is left as the piece has it, so a preset taken out of it
		does not come back.
	**/
	static function shipped():Void {
		final library = Library.embedded();
		final song = new Song();
		library.into(song);

		final at = library.names.length == 0 ? "" : library.names[0];
		var bank:Null<mdd.song.Bank> = null;

		for (held in song.banks) if (held.name == at) bank = held;

		if (bank == null || bank.instruments.length < 2) {
			says("a shipped bank is left as it is", false, "no shipped bank to try");
			return;
		}

		final before = bank.instruments.length;
		bank.remove(bank.instruments[0]);

		final added = library.into(song);

		says("a shipped bank is left as it is", added == 0 && bank.instruments.length == before - 1,
			added + " added back into '" + at + "', which holds " + bank.instruments.length);
	}

	/**
		A piece read from a file has its presets filed by where they came from: the library's own
		banks for what the library offers, the starting bank for the set every piece begins with,
		and one bank for what the file itself brought, however the file had them grouped. A piece
		carrying the same preset twice, as one written before the presets folder had a name of its
		own does, lists it once.
	**/
	static function filed():Void {
		final library = Library.embedded();
		library.keeps(SAVED, patched("My Own Lead"), null);

		final song = new Song("my piece");
		mdd.song.Shipped.into(song);

		final shippedBank = library.names.length == 0 ? "" : library.names[0];
		final fromShipped = library.instruments[0][0].name;

		library.into(song);

		final starter = listed(song, Library.STARTERS);
		final mine = song.instrument(patched("Bass Of Mine"));
		final swapped = song.instrument(enveloped("Square Of Mine", Part.Psg1));
		final imported = song.instrument(patched("Lead Of Mine"));

		final named = song.banked("my piece");
		final blank = song.banked("");
		final importing = song.banked("from the import");

		song.bank(0).remove(song.instruments.length - 1);
		song.bank(0).remove(song.instruments.length - 2);
		song.bank(0).remove(song.instruments.length - 3);

		named.add(song.instruments.indexOf(mine));
		named.add(song.instruments.indexOf(swapped));
		importing.add(song.instruments.indexOf(imported));

		for (index in song.banked(shippedBank).instruments) named.add(index);
		for (index in song.banked(SAVED).instruments) blank.add(index);

		final twin = song.instrument(patched("My Own Lead"));
		song.bank(0).remove(song.instruments.indexOf(twin));
		blank.add(song.instruments.indexOf(twin));

		final was = song.instruments.length;
		final rack = song.rack[0];

		library.files(song, FROM_FILE);
		final added = library.into(song);

		says("what the file brought is one bank", listed(song, FROM_FILE)
			== "Bass Of Mine, Square Of Mine, Lead Of Mine",
			"'" + FROM_FILE + "' holds " + listed(song, FROM_FILE) + ", from a bank named after the piece and one"
			+ " named for an import");

		says("a shipped preset goes back to its bank", listed(song, shippedBank).indexOf(fromShipped) >= 0
			&& listed(song, "my piece") == "" && listed(song, "") == "",
			"'" + fromShipped + "' is in '" + shippedBank + "' again, and the banks named after the piece and after"
			+ " nothing are empty");

		says("a preset carried twice is listed once", listed(song, SAVED) == "My Own Lead",
			"'" + SAVED + "' holds " + listed(song, SAVED) + " for a piece carrying it twice");

		says("the starting presets stay where they are", listed(song, Library.STARTERS) == starter,
			Library.STARTERS + " holds the same " + song.banked(Library.STARTERS).instruments.length + " presets");

		says("nothing a note names moves", song.instruments.length == was && added == 0
			&& song.rack[0] == rack,
			song.instruments.length + " instruments before and after, " + added + " added by the library afterwards,"
			+ " and the rack still names " + rack);

		kitted();
	}

	/**
		A kit is the one thing a bank decides rather than only shows: a converter note sounds the
		hit in the bank the rack's converter preset sits in. A kit gathered from a reader's own
		hits and one borrowed out of a shipped kit is therefore still one kit after filing, and
		every key it was written across still sounds.
	**/
	static function kitted():Void {
		final library = Library.embedded();
		final song = new Song("kitted");

		mdd.song.Shipped.into(song);
		library.into(song);

		final borrowed = bankOf(song, library.names.length == 0 ? "" : shippedKit(library));
		if (borrowed < 0) {
			says("a kit gathered from several places stays one kit", false, "no shipped kit to borrow from");
			return;
		}

		final taken = song.instrumentAt(borrowed);
		final played = song.sampleAt(taken.sample);

		final own = song.banked("my piece");
		final roots:Array<Int> = [];

		for (index in 0...3) {
			final made = new Instrument("Hit " + index, Part.Dac);
			final sample = sampled("Hit " + index);

			sample.root = 40 + index;
			song.sample(sample);

			made.sample = song.samples.length - 1;
			song.instrument(made);

			final held = song.instruments.length - 1;

			song.bank(0).remove(held);
			own.add(held);
			roots.push(sample.root);
		}

		for (bank in song.banks) bank.remove(borrowed);
		own.add(borrowed);

		song.rack[Part.Dac.index()] = song.instruments.length - 1;
		song.drums = true;

		if (played != null) roots.push(played.root);

		var before = 0;
		for (root in roots) if (song.drumAt(root) >= 0) before++;

		library.files(song, FROM_FILE);
		library.into(song);

		var after = 0;
		for (root in roots) if (song.drumAt(root) >= 0) after++;

		says("a kit gathered from several places stays one kit", before == roots.length
			&& after == roots.length,
			after + " of " + roots.length + " keys still sound after filing, against " + before + " before, on a kit"
			+ " of a reader's own hits and one taken out of " + FROM_FILE);
	}

	/**
		@param library A library.
		@return The name of the first bank in it holding a converter preset with a sample.
	**/
	static function shippedKit(library:Library):String {
		for (at in 0...library.names.length) {
			for (which in 0...library.instruments[at].length) {
				if (library.samples[at][which] != null) return library.names[at];
			}
		}

		return "";
	}

	/**
		@param song A song.
		@param bank A bank's name.
		@return The first converter preset in it, by index into the song, or -1.
	**/
	static function bankOf(song:Song, bank:String):Int {
		if (bank == "") return -1;

		for (held in song.banks) {
			if (held.name != bank) continue;

			for (index in held.instruments) {
				final one = song.instrumentAt(index);
				if (one != null && one.kind.sampled() && one.sample >= 0) return index;
			}
		}

		return -1;
	}

	/**
		A preset is what everything in it says rather than what it is called. Two presets differing
		anywhere differ in identity, two the same in every field are the same preset wherever each
		sits, and a channel edited in a piece is no longer the preset it started as, which is what
		lets a project carry its own and a reader keep theirs.
	**/
	static function identified():Void {
		final one = patched("Bass");
		final two = patched("Bass");

		one.identifies(null);
		two.identifies(null);

		final alike = one.id == two.id && one.id.length == 32;

		two.patch.totalLevel[3] = two.patch.totalLevel[3] + 1;
		final level = two.identifies(null);

		two.patch.totalLevel[3] = one.patch.totalLevel[3];
		two.name = "Bass 2";
		final named = two.identifies(null);

		two.name = "Bass";
		two.tags.push("soft");
		final tagged = two.identifies(null);

		two.tags.pop();
		two.icon = one.icon + 1;
		final iconed = two.identifies(null);

		says("an identity is everything the preset holds", alike && level != one.id
			&& named != one.id && tagged != one.id && iconed != one.id
			&& level != named && named != tagged && tagged != iconed,
			"two presets written the same way answer " + one.id.substr(0, 8) + ", and a total level, a"
			+ " name, a tag and an icon each answer something else");

		final held = enveloped("Pulse", Part.Psg1);
		held.identifies(null);

		final was = held.id;
		held.envelope.steps.push(3);
		final stepped = held.identifies(null);

		held.envelope.steps.pop();
		held.envelope.speed = held.envelope.speed + 1;
		final sped = held.identifies(null);

		final hit = new Instrument("Hit", Part.Dac);
		final sample = sampled("Hit");

		hit.identifies(sample);
		final heard = hit.id;

		sample.bytes[17] = (sample.bytes[17] + 1) & 0xFF;
		final struck = hit.identifies(sample);

		says("and that reaches an envelope and a recording", stepped != was && sped != was
			&& stepped != sped && struck != heard,
			"a step, a speed and one byte of a recording each answer something else");

		final song = new Song("carrying");
		final own = song.instrument(patched("Bass"));

		own.patch.feedback = 6;
		own.identifies(null);
		own.from = one.id;

		song.bank(0).remove(song.instruments.length - 1);
		song.banked(FROM_FILE).add(song.instruments.length - 1);

		final library = new Library();
		library.reads(Library.saved(patched("Bass"), null), true, SAVED);

		final added = library.into(song);
		final kept = song.instrumentAt(song.instruments.indexOf(own));

		says("a piece keeps its own against a reader's", kept != null && kept.patch.feedback == 6
			&& listed(song, FROM_FILE) == "Bass" && added == 1 && kept.from == one.id,
			"the piece still plays its own Bass at a feedback of " + (kept == null ? -1 : kept.patch.feedback)
			+ ", the folder's arrived beside it as " + added + " more, and the piece's still says it came"
			+ " from " + one.id.substr(0, 8));
	}

	/**
		Every kind of preset there is survives being written as records and read back: a patch with
		every field away from its default, an envelope with a loop and a noise of its own, and a
		recording with an odd length and a loop part way through it. Identity answers for all of
		it at once, because it is worked out over everything a preset holds.
	**/
	static function recorded(root:String):Void {
		final patch = patched("Round");
		final square = enveloped("Pulse", Part.Psg1);
		final noise = enveloped("Tick", Part.Noise);
		final hit = new Instrument("Thud", Part.Dac);
		final sample = sampled("Thud");

		patch.tags.push("warm");
		patch.tags.push("soft");
		patch.patch.tremolo[2] = true;

		square.envelope.loop = 3;
		square.envelope.speed = 5;
		noise.envelope.noise = 7;
		sample.loop = 121;

		final held = [patch, square, noise, hit];
		final playing:Array<Null<mdd.song.Sample>> = [null, null, null, sample];

		for (index in 0...held.length) held[index].identifies(playing[index]);

		final written = mdd.format.Preset.write("Everything", held, playing);
		final back = mdd.format.Preset.read(written);

		if (back == null) {
			says("every kind of preset survives records", false, "the file did not read back");
			return;
		}

		var same = 0;
		var bytes = 0;

		for (index in 0...back.presets.length) {
			if (back.presets[index].id == held[index].id) same++;
		}

		final taken = back.samples[3];
		if (taken != null) {
			for (at in 0...taken.length()) if (taken.bytes[at] == sample.bytes[at]) bytes++;
		}

		says("every kind of preset survives records", back.name == "Everything"
			&& back.presets.length == 4 && same == 4 && taken != null
			&& taken.length() == sample.length() && bytes == sample.length()
			&& taken.loop == sample.loop && taken.rate == sample.rate,
			same + " of 4 read back as the same preset they went in as, and the recording's "
			+ bytes + " of " + sample.length() + " bytes with its loop at "
			+ (taken == null ? -1 : taken.loop));

		says("and what is not a preset file is not read",
			mdd.format.Preset.read(haxe.io.Bytes.ofString("not a preset at all")) == null
			&& mdd.format.Preset.read(null) == null,
			"a file that does not open with the right four bytes reads as nothing");
	}

	/**
		The banks the application ships are kept as documents and carried as records. Every preset
		has to come across exactly, or what a reader browses is not what was written for them.
	**/
	static function carriedOver(root:String):Void {
		final documents = new Library();
		final where = root + "/assets/presets";

		if (!sys.FileSystem.exists(where)) {
			says("every shipped preset comes across", false, "no bank documents to read");
			return;
		}

		var text = 0;

		for (name in sys.FileSystem.readDirectory(where)) {
			if (!StringTools.endsWith(name.toLowerCase(), Library.SUFFIX)) continue;

			text += sys.io.File.getContent(where + "/" + name).length;
			documents.reads(sys.io.File.getContent(where + "/" + name));
		}

		final records = Library.embedded();
		var carried = 0;
		var missing = "";

		for (at in 0...documents.names.length) {
			final which = records.names.indexOf(documents.names[at]);

			if (which < 0) {
				missing = documents.names[at];
				continue;
			}

			for (one in documents.instruments[at]) {
				var found = false;

				for (two in records.instruments[which]) if (one.id == two.id) found = true;

				if (found) carried++;
				else if (missing == "") missing = one.name;
			}
		}

		var built = 0;

		for (name in haxe.Resource.listNames()) {
			if (name.length > 5 && name.substr(0, 5) == "bank.") built += haxe.Resource.getBytes(name).length;
		}

		says("every shipped preset comes across", carried == documents.count()
			&& documents.count() > 0 && missing == "",
			carried + " of " + documents.count() + " presets are the same preset as records"
			+ (missing == "" ? "" : ", missing " + missing));

		var quickest = 1000.0;

		for (pass in 0...7) {
			final began = Sys.time();
			Library.embedded();
			final took = Sys.time() - began;

			if (took < quickest) quickest = took;
		}

		says("and records are smaller than documents", built < text && built > 0,
			built + " bytes of records against " + text + " of documents, "
			+ Math.round(100 - built * 100 / text) + " per cent less, read in "
			+ Math.round(quickest * 100000) / 100 + " ms, best of 7");
	}

	/**
		Loading a preset into a channel takes a copy of it, so playing with the channel leaves the
		preset as it was written and choosing it again puts the channel back. That is what a piece
		needs to carry its own presets: the copy says which preset it came from, and the preset is
		in the piece, so neither needs a reader's own folder.
	**/
	static function loaded():Void {
		final song = new Song("loading");
		final lead = song.instrument(patched("Lead"));

		lead.identifies(null);

		final at = song.instruments.indexOf(lead);
		final was = song.instruments.length;

		final take = new mdd.song.edit.TakesPreset(Part.Fm1, at);
		take.apply(song);

		final playing = song.instrumentAt(song.rack[Part.Fm1.index()]);
		final copied = playing != null && playing != lead && playing.from == lead.id
			&& song.instruments.length == was + 1;

		says("loading a preset takes a copy of it", copied,
			copied ? "the channel plays its own copy, which says it came from " + lead.id.substr(0, 8)
			: "the channel plays the preset itself");

		if (playing == null || playing.patch == null || lead.patch == null) return;

		final feedback = lead.patch.feedback;

		playing.patch.feedback = feedback == 7 ? 1 : 7;
		playing.name = "Lead I Changed";
		playing.identifies(null);

		says("and playing with the channel leaves the preset alone",
			lead.patch.feedback == feedback && lead.name == "Lead",
			"the preset still reads " + lead.name + " at a feedback of " + lead.patch.feedback);

		final grew = song.instruments.length;

		final again = new mdd.song.edit.TakesPreset(Part.Fm1, at);
		again.apply(song);

		final back = song.instrumentAt(song.rack[Part.Fm1.index()]);

		says("and choosing it again puts the channel back", back != null
			&& back.patch.feedback == feedback && back.name == "Lead"
			&& song.instruments.length == grew,
			"the channel reads " + (back == null ? "nothing" : back.name + " at a feedback of "
			+ back.patch.feedback) + ", and no second copy was made");

		again.revert(song);

		final edited = song.instrumentAt(song.rack[Part.Fm1.index()]);

		says("and undo brings back what was played with", edited != null
			&& edited.patch.feedback != feedback && edited.name == "Lead I Changed",
			"undone, the channel reads " + (edited == null ? "nothing" : edited.name
			+ " at a feedback of " + edited.patch.feedback));
	}

	/**
		A folder with subfolders reads as one bank per subfolder.
	**/
	static function folded(where:String):Void {
		sys.FileSystem.createDirectory(where + "/Bass");
		sys.FileSystem.createDirectory(where + "/Bass/Soft");

		sys.io.File.saveContent(where + "/Lead.json", Library.saved(patched("Lead"), null));
		sys.io.File.saveContent(where + "/Bass/Sub.json", Library.saved(patched("Sub"), null));
		sys.io.File.saveBytes(where + "/Bass/Slap.tfi", mdd.format.Tfi.write(patched("Slap").patch));
		sys.io.File.saveContent(where + "/Bass/Soft/Round.json",
			Library.saved(patched("Round"), null));

		final library = new Library();
		final many = library.within(where, SAVED);

		final banks:Array<String> = [];

		for (at in 0...library.names.length) {
			final held:Array<String> = [];
			for (one in library.instruments[at]) held.push(one.name);

			banks.push(library.names[at] + " (" + held.join(", ") + ")");
		}

		says("each subfolder is a bank", many == 4 && banks.join("; ")
			== SAVED + " (Lead); Bass (Slap, Sub); Bass / Soft (Round)", banks.join("; "));
	}

	/**
		The presets folder is laid out with a folder for each family of part. Those four stand for
		no bank of their own: what is loose in one is saved, and a folder inside one is a bank
		named for itself, the same as a folder at the top.
	**/
	static function familied(where:String):Void {
		mdd.host.Paths.clear(where);
		mdd.host.Paths.make(where);

		sys.FileSystem.createDirectory(where + "/FM");
		sys.FileSystem.createDirectory(where + "/FM/Leads");
		sys.FileSystem.createDirectory(where + "/PSG");

		sys.io.File.saveContent(where + "/FM/Plain.json", Library.saved(patched("Plain"), null));
		sys.io.File.saveContent(where + "/FM/Leads/Bright.json", Library.saved(patched("Bright"), null));
		sys.io.File.saveContent(where + "/PSG/Pulse.json",
			Library.saved(enveloped("Pulse", Part.Psg1), null));

		final library = new Library();
		final many = library.within(where, SAVED);
		final banks:Array<String> = [];

		for (at in 0...library.names.length) {
			final held:Array<String> = [];
			for (one in library.instruments[at]) held.push(one.name);

			banks.push(library.names[at] + " (" + held.join(", ") + ")");
		}

		banks.sort(function(one:String, two:String):Int return one < two ? -1 : 1);

		says("a folder for each family is not a bank", many == 3
			&& banks.join("; ") == "Leads (Bright); " + SAVED + " (Plain, Pulse)",
			banks.join("; "));
	}

	/**
		What was in a presets folder before it was laid out by family is moved into it, a bank
		document of one family with it, because a bank document is its own bank wherever it sits.
		One carrying more than one family stays where it is, because no one folder is its place.
	**/
	static function sortedIn(where:String):Void {
		mdd.host.Paths.clear(where);
		mdd.host.Paths.make(where);

		sys.FileSystem.createDirectory(where + "/Bass");

		sys.io.File.saveContent(where + "/Lead.json", Library.saved(patched("Lead"), null));
		sys.io.File.saveBytes(where + "/Slap.tfi", mdd.format.Tfi.write(patched("Slap").patch));
		sys.io.File.saveContent(where + "/Bass/Sub.json", Library.saved(patched("Sub"), null));
		sys.io.File.saveContent(where + "/Beeps.json",
			Library.saved(enveloped("Beeps", Part.Psg1), null));
		sys.io.File.saveContent(where + "/Hits.json",
			Library.saved(enveloped("Hits", Part.Noise), null));

		sys.io.File.saveContent(where + "/Kit.json",
			banked("A Kit Of Its Own", [enveloped("Tick", Part.Noise)]));

		sys.io.File.saveContent(where + "/Both.json",
			banked("Two Families", [patched("Wide"), enveloped("Narrow", Part.Psg1)]));

		final files = new mdd.app.Files(new mdd.app.Session(new Song()));
		files.presetsAt = where;

		final moved = files.sortsPresets();

		final landed = sys.FileSystem.exists(where + "/FM/Lead.json")
			&& sys.FileSystem.exists(where + "/FM/Slap.tfi")
			&& sys.FileSystem.exists(where + "/FM/Bass/Sub.json")
			&& sys.FileSystem.exists(where + "/PSG/Beeps.json")
			&& sys.FileSystem.exists(where + "/NOISE/Hits.json")
			&& sys.FileSystem.exists(where + "/NOISE/Kit.json");

		final stayed = sys.FileSystem.exists(where + "/Both.json")
			&& !sys.FileSystem.exists(where + "/Lead.json");

		says("what was there is sorted by family", moved == 6 && landed && stayed,
			moved + " files moved, each under the folder its family stands in, the subfolder they"
			+ " were in kept, a bank document of one family with them, and the one carrying two"
			+ " families left where it is");

		final again = files.sortsPresets();

		says("and sorting again moves nothing", again == 0,
			again + " files moved the second time, because everything is already where it belongs");
	}

	/**
		@param name What the bank is called.
		@param held What is in it.
		@return The bank as a document, the way one written by hand into the presets folder reads.
	**/
	static function banked(name:String, held:Array<Instrument>):String {
		final said:Array<String> = [];

		for (one in held) {
			final whole = Library.saved(one, null);
			final from = whole.indexOf("[") + 1;

			said.push(whole.substring(from, whole.lastIndexOf("]")));
		}

		return "{\"name\": " + haxe.Json.stringify(name) + ", \"presets\": ["
			+ said.join(",") + "]}";
	}

	/**
		A preset moved into a subfolder leaves the bank it was in, in the piece that is open, and
		one edited in the piece stays where it is.
	**/
	static function moved(where:String):Void {
		mdd.host.Paths.clear(where);
		mdd.host.Paths.make(where);

		sys.io.File.saveContent(where + "/Lead.json", Library.saved(patched("Lead"), null));
		sys.io.File.saveContent(where + "/Keys.json", Library.saved(patched("Keys"), null));

		final library = new Library();
		library.within(where, SAVED);

		final song = new Song();
		library.into(song);

		for (held in song.instruments) {
			if (held.name == "Keys" && held.patch != null) held.patch.feedback = 2;
		}

		sys.FileSystem.createDirectory(where + "/Leads");
		sys.FileSystem.rename(where + "/Lead.json", where + "/Leads/Lead.json");
		sys.FileSystem.createDirectory(where + "/Keys");
		sys.FileSystem.rename(where + "/Keys.json", where + "/Keys/Keys.json");

		final count = song.instruments.length;
		final before = library.sheds();

		library.within(where, SAVED);

		final added = library.into(song);
		final gone = library.prunes(song, before);

		final saved = listed(song, SAVED);
		final leads = listed(song, "Leads");

		says("a preset moved into a subfolder moves", gone == 1 && leads == "Lead"
			&& saved == "Keys" && song.instruments.length == count + added,
			added + " added, " + gone + " left; " + SAVED + " holds " + saved + ", Leads holds "
			+ leads);
	}

	/**
		The browser's save writes a file of its own into the presets folder, writes over its own
		file when saved again, and never over a bank of the same name.
	**/
	static function written(where:String):Void {
		mdd.host.Paths.clear(where);
		mdd.host.Paths.make(where);

		final song = new Song();
		final files = new mdd.app.Files(new mdd.app.Session(song));
		final library = new Library();

		files.presetsAt = where;
		files.savedInto = SAVED;
		files.library = library;

		sys.FileSystem.createDirectory(where + "/FM");

		final other = patched("Kit");
		other.identifies(null);

		sys.io.File.saveBytes(where + "/FM/Drums" + Library.RECORDS,
			mdd.format.Preset.write("", [other], [null]));

		final first = files.keepsPreset(patched("Drums"), null);
		final again = patched("Drums");
		again.patch.algorithm = 3;
		final second = files.keepsPreset(again, null);
		final third = files.keepsPreset(patched("Bell"), null);

		final held = mdd.format.Preset.read(sys.io.File.getBytes(where + "/FM/Drums" + Library.RECORDS));
		final kept = held != null && held.presets.length == 1 && held.presets[0].name == "Kit";

		final named = mdd.app.Files.name(first) + ", " + mdd.app.Files.name(second) + ", "
			+ mdd.app.Files.name(third);

		final at = library.names.indexOf(SAVED);
		final taken:Array<Instrument> = at < 0 ? [] : library.instruments[at];
		final shown:Array<String> = [];

		for (one in taken) shown.push(one.name + " " + one.patch.algorithm);

		final fresh = new Library();
		fresh.within(where, SAVED);

		final reread = fresh.names.indexOf(SAVED);
		final back = reread < 0 ? 0 : fresh.instruments[reread].length;

		says("a saved preset is written beside what is there", kept && named
			== "Drums 2" + Library.RECORDS + ", Drums 2" + Library.RECORDS + ", Bell" + Library.RECORDS
			&& shown.join(", ") == "Drums 3, Bell 7" && back == 3,
			named + "; library holds " + shown.join(", ") + "; " + back
			+ " read back from the folder, and the file that was already there "
			+ (kept ? "still holds Kit" : "was written over"));
	}

	/**
		A patch travels to a patch file and back with nothing lost, and a preset read from one is
		the patch the file holds.

		A patch file is forty two bytes of register values and carries no name, no tags and none
		of the three the piece keeps beside the registers: the two LFO sensitivities and which
		operators the LFO reaches. Those are the format rather than the writer, and what the round
		trip has to show is that everything the format does carry comes back exactly.
	**/
	static function converted():Void {
		final made = patched("Glass Lead");
		final bytes = mdd.format.Tfi.write(made.patch);
		final back = mdd.format.Tfi.read(bytes);

		says("a patch goes to a patch file and back", bytes.length == mdd.format.Tfi.BYTES
			&& back != null && mdd.format.Tfi.same(made.patch, back),
			mdd.format.Tfi.BYTES + " bytes, and every field the format carries matches");

		final one = new Instrument("Glass Lead", Part.Fm1);
		one.patch = back;

		final records = mdd.format.Preset.write("", [one], [null]);
		final held = mdd.format.Preset.read(records);
		final kept = held == null || held.presets.length != 1 ? null : held.presets[0].patch;

		says("and on through a preset file", kept != null && mdd.format.Tfi.same(made.patch, kept),
			"a patch file read in and written out as a preset is the same patch");

		says("and the three it cannot carry are the format",
			made.patch.ams == 2 && made.patch.pms == 5 && back.ams == 0 && back.pms == 0,
			"the piece holds an LFO depth of " + made.patch.ams + " and " + made.patch.pms
			+ ", a patch file holds neither");
	}

	/**
		A star is on a preset rather than on a row, so it follows the preset and it does not
		follow an edit.
	**/
	static function starred():Void {
		final held = new mdd.app.Favourites();
		final one = patched("Glass Lead");
		final two = enveloped("Blip", Part.Psg1);

		one.identifies(null);
		two.identifies(null);

		var wrote = 0;
		held.onChange = function():Void wrote++;

		held.favour(one.id, true);
		held.favour(one.id, true);
		held.favour(two.id, true);

		says("a star is kept once", held.count() == 2 && wrote == 2,
			held.count() + " starred after three asks, written " + wrote + " times");

		final back = new mdd.app.Favourites();
		back.reads(held.spelt());

		says("and it reads back as it was written", back.count() == 2 && back.favours(one.id)
			&& back.favours(two.id) && back.spelt() == held.spelt(),
			held.spelt());

		final edited = one.copy();
		edited.patch.feedback = 1;
		edited.id = "";
		edited.identifies(null);

		says("and an edit is a different preset", !back.favours(edited.id)
			&& edited.id != one.id,
			"starred " + one.id + ", edited into " + edited.id);

		back.toggles(one.id);

		says("and a star comes off", !back.favours(one.id) && back.count() == 1,
			back.count() + " left");
	}

	/**
		The three things the browser writes out: a preset as a patch file, what a converter preset
		plays as a wave file, and a whole bank as one file, which reads back into a piece that has
		none of them.
	**/
	static function poured(where:String):Void {
		mdd.host.Paths.clear(where);
		mdd.host.Paths.make(where);

		final song = new Song();
		final session = new mdd.app.Session(song);
		final files = new mdd.app.Files(session);

		files.presetsAt = where + "/presets";
		files.savedInto = SAVED;

		final lead = patched("Glass Lead");
		final hit = enveloped("Blip", Part.Psg1);
		final drum = new Instrument("Kick", Part.Dac);

		lead.identifies(null);

		song.sample(sampled("kick"));
		drum.sample = song.samples.length - 1;

		song.instrument(lead);
		final leadAt = song.instruments.length - 1;

		song.instrument(hit);
		song.instrument(drum);
		final drumAt = song.instruments.length - 1;

		final bank = song.banked("Kit");

		for (index in [leadAt, leadAt + 1, drumAt]) {
			song.bank(0).remove(index);
			bank.add(index);
		}

		files.chosen = leadAt;
		final wrotePatch = files.writesPresetTfi(where + "/Glass Lead");

		files.chosen = drumAt;
		final wroteWave = files.writesPresetWav(where + "/Kick");

		files.chosen = song.banks.indexOf(bank);
		final wroteBank = files.writesBank(where + "/Kit");

		final patch = mdd.format.Tfi.read(sys.io.File.getBytes(wrotePatch));
		final wave = sys.io.File.getBytes(wroteWave);
		final frames = wave == null ? 0 : (wave.length - 44);

		says("a preset is written out as a patch file", patch != null
			&& mdd.format.Tfi.same(lead.patch, patch),
			mdd.app.Files.name(wrotePatch) + ", " + mdd.format.Tfi.BYTES + " bytes");

		says("and what a hit plays as a wave file", frames == sampled("kick").length() * 2
			&& wave.getString(0, 4) == "RIFF",
			mdd.app.Files.name(wroteWave) + ", " + frames + " bytes of sound at "
			+ sampled("kick").rate + " hertz");

		final other = new Song();
		final reading = new mdd.app.Files(new mdd.app.Session(other));

		reading.presetsAt = where + "/read";
		reading.savedInto = SAVED;
		reading.readPresets(wroteBank);

		says("and a bank reads back into a piece with none of it",
			listed(other, "Kit") == "Glass Lead, Blip, Kick" && other.samples.length == 1,
			listed(other, "Kit") + "; " + other.samples.length + " recording");

		final home = other.identified(lead.id);

		says("and it is the same preset it was written from", home != null
			&& home.name == "Glass Lead" && mdd.format.Tfi.same(lead.patch, home.patch),
			"identity " + lead.id + " on both sides");

		mdd.host.Paths.clear(where);
	}

	/**
		Lifting a piece's patches into the presets folder keeps everything a patch file cannot,
		and lifting the same piece again writes nothing.
	**/
	static function raised(where:String):Void {
		mdd.host.Paths.clear(where);
		mdd.host.Paths.make(where);

		final song = new Song();
		final files = new mdd.app.Files(new mdd.app.Session(song));
		final library = new Library();

		files.presetsAt = where;
		files.savedInto = SAVED;
		files.library = library;

		final one = patched("Glass Lead");
		final two = patched("Glass Lead");
		two.patch.feedback = 1;

		song.instrument(one);
		song.instrument(two);

		final first = files.liftsPatches();
		final again = files.liftsPatches();

		final fresh = new Library();
		fresh.within(where, SAVED);

		final at = fresh.names.indexOf(SAVED);
		final held:Array<Instrument> = at < 0 ? [] : fresh.instruments[at];
		final shown:Array<String> = [];

		for (kept in held) {
			shown.push(kept.name + " " + kept.patch.feedback + " " + kept.patch.ams + "/"
				+ kept.patch.pms + " " + kept.tags.join("+"));
		}

		says("lifting keeps what a patch file cannot", first == 2 && shown.join(", ")
			== "Glass Lead 1 2/5 Lead+Bright, Glass Lead 5 2/5 Lead+Bright"
			&& held.length == 2 && held[0].icon == one.icon,
			first + " written, read back as " + shown.join(", ") + ", both with icon "
			+ (held.length == 0 ? -1 : held[0].icon));

		says("and lifting the same piece again writes nothing", again == 0,
			again + " written the second time");

		mdd.host.Paths.clear(where);
	}

	/**
		A folder read once is read back from one file, and the file is thrown away the moment the
		folder stops matching it.

		A reader's own folder is hundreds of patch files, each of which is an open, a read and a
		close, and the cost is paid at every start. What the cache holds is what was read rather
		than what is on disk, so what it has to show is that both sides answer the same presets.
	**/
	static function keptBack(where:String):Void {
		mdd.host.Paths.clear(where);
		mdd.host.Paths.make(where);

		final folder = where + "/presets";
		final many = 368;

		mdd.host.Paths.make(folder + "/FM/Leads");
		mdd.host.Paths.make(folder + "/DAC");

		for (index in 0...many) {
			final one = patched("Patch " + index);
			one.patch.feedback = index & 7;

			sys.io.File.saveBytes(folder + "/FM/Leads/Patch " + index + Library.PATCH,
				mdd.format.Tfi.write(one.patch));
		}

		final drum = new Instrument("Kick", Part.Dac);

		sys.io.File.saveBytes(folder + "/DAC/Kit" + Library.BANK,
			mdd.format.Preset.write("Kit", [drum], [sampled("kick")]));

		final cache = where + "/presets.cache";
		final stamp = stamping(folder);

		final read = new Library();
		var cost = 1e9;

		for (round in 0...ROUNDS) {
			final one = new Library();
			final opened = haxe.Timer.stamp();

			one.within(folder, SAVED);

			final took = (haxe.Timer.stamp() - opened) * 1000;
			if (took < cost) cost = took;
		}

		read.within(folder, SAVED);
		read.caches(cache, stamp);

		final back = new Library();
		var quick = 1e9;
		var carried = 0;

		for (round in 0...ROUNDS) {
			final one = new Library();
			final again = haxe.Timer.stamp();

			carried = one.cached(cache, stamp);

			final took = (haxe.Timer.stamp() - again) * 1000;
			if (took < quick) quick = took;
		}

		back.cached(cache, stamp);

		says("a folder is read back from one file", carried == read.count()
			&& back.count() == read.count() && back.names.length == read.names.length,
			carried + " of " + read.count() + " presets in " + back.names.length
			+ " banks, read in " + Math.round(quick * 10) / 10 + " ms against "
			+ Math.round(cost * 10) / 10 + " ms for " + (many + 1) + " files, best of "
			+ ROUNDS + ", " + Math.round(cost / quick * 10) / 10 + " times faster");

		final leads = back.names.indexOf("Leads");
		final kit = back.names.indexOf("Kit");
		final hit = kit < 0 ? null : back.samples[kit][0];

		says("and it is the same presets it was written from", leads >= 0 && kit >= 0
			&& back.instruments[leads].length == many && hit != null
			&& hit.length() == sampled("kick").length() && back.owned[leads],
			"Leads holds " + (leads < 0 ? 0 : back.instruments[leads].length)
			+ ", Kit holds a recording of " + (hit == null ? 0 : hit.length()) + " bytes");

		sys.io.File.saveBytes(folder + "/FM/Leads/One More" + Library.PATCH,
			mdd.format.Tfi.write(patched("One More").patch));

		final stale = new Library();
		final answer = stale.cached(cache, stamping(folder));

		says("and one more file throws the cache away", answer < 0 && stale.count() == 0,
			"the cache answers " + answer + ", so the folder is read again");

		mdd.host.Paths.clear(where);
	}

	/**
		@param where A folder.
		@return What it lists, the way the application stamps the presets folder.
	**/
	static function stamping(where:String):String {
		final files = new mdd.app.Files(new mdd.app.Session(new Song()));
		files.presetsAt = where;

		return files.presetsStamp();
	}

	/**
		@param song A piece.
		@param name One of its banks.
		@return The names of the presets in it, in order.
	**/
	static function listed(song:Song, name:String):String {
		final out:Array<String> = [];

		for (bank in song.banks) {
			if (bank.name != name) continue;

			for (index in bank.instruments) {
				final held = song.instrumentAt(index);
				if (held != null) out.push(held.name);
			}
		}

		return out.join(", ");
	}

	/**
		@param name What to call it.
		@return An FM preset with every field away from its default, LFO depths included.
	**/
	static function patched(name:String):Instrument {
		final out = new Instrument(name, Part.Fm1);
		final patch = out.patch;

		patch.algorithm = 7;
		patch.feedback = 5;
		patch.ams = 2;
		patch.pms = 5;

		for (slot in 0...mdd.song.Patch.SLOTS) {
			patch.detune[slot] = slot + 1;
			patch.multiple[slot] = slot * 3 + 1;
			patch.totalLevel[slot] = 20 + slot * 9;
			patch.keyScale[slot] = slot & 3;
			patch.attack[slot] = 31 - slot;
			patch.decay[slot] = 10 + slot;
			patch.sustain[slot] = 4 + slot;
			patch.sustainLevel[slot] = 3 + slot;
			patch.release[slot] = 8 + slot;
			patch.ssg[slot] = slot == 2 ? 9 : 0;
			patch.tremolo[slot] = slot == 1;
		}

		out.icon = mdd.Icon.NAMES.indexOf("synthesizer");
		out.tags.push("Lead");
		out.tags.push("Bright");

		return out;
	}

	/**
		@param name What to call it.
		@param kind A square part or the noise part.
		@return A preset with a drawn envelope, a loop and a speed.
	**/
	static function enveloped(name:String, kind:Part):Instrument {
		final out = new Instrument(name, kind);
		final envelope = out.envelope;

		for (step in 0...12) envelope.steps.push(15 - step);

		envelope.turns(Envelope.LOOP, 4);
		envelope.turns(Envelope.SPEED, 3);
		if (kind.noise()) envelope.turns(Envelope.NOISE, 6);

		out.tags.push("Short");
		return out;
	}

	/**
		@param name What to call it.
		@return A short sample with a loop point.
	**/
	static function sampled(name:String):Sample {
		final out = new Sample(name, 13000, 38);
		final bytes = new haxe.ds.Vector<Int>(700);

		for (at in 0...bytes.length) bytes[at] = (at * 13 + 5) & 0xFF;

		out.hold(bytes);
		out.loop = 120;

		return out;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 42) + said + (ok ? "" : "   FAILED"));
	}
}
