package mdd.gate;

import mdd.format.Project;
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
	and nothing a patch or an envelope holds may be lost on the way. A piece holds a preset once it
	is loaded and not before. A folder with subfolders reads as one bank per subfolder, and a preset
	moved into a subfolder in the file manager moves to that bank.
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
		identified();
		released();
		recorded(Gate.root);
		carriedOver(Gate.root);
		loaded();
		rackCopied();
		converted();
		starred();

		final where = Gate.root + "/export/gate/presets";
		mdd.host.Paths.clear(where);
		mdd.host.Paths.make(where);

		folded(where);
		moved(where);
		written(where);
		poured(where);
		opened();
		likened();
		echoed(where);
		raised(where);
		fitted(where);
		keptBack(where);
		familied(where);
		sortedIn(where);
		dated(where);
		organised(where);
		imported(where);
		planted(where);
		spared(where);

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
		A preset saved while one piece is open is offered to every piece from then on, and saving
		one of the same name again takes its place rather than listing it twice.
	**/
	static function reached():Void {
		final library = new Library();
		library.reads(Library.saved(patched("Old Bass"), null), true, SAVED);

		library.keeps(SAVED, patched("New Lead"), null);
		library.keeps(SAVED, patched("New Lead"), null);

		final at = library.names.indexOf(SAVED);
		final names:Array<String> = [];

		for (held in (at < 0 ? [] : library.instruments[at])) names.push(held.name);

		says("a saved preset is offered from then on", names.join(",") == "Old Bass,New Lead",
			SAVED + " offers " + names.join(", ") + " after New Lead was saved twice");
	}

	/**
		A preset or a kit reaches a piece when it is loaded and not before. Loading copies it in,
		a kit whole, and loading the same kit again finds the copy already there.
	**/
	static function shipped():Void {
		final library = Gate.library();
		final song = new Song();
		final kit = shippedKit(library);
		final at = library.names.indexOf(kit);

		if (at < 0) {
			says("a kit arrives whole, once", false, "no shipped kit to load");
			return;
		}

		final before = song.instruments.length;
		final hits = library.instruments[at];
		final played = library.samples[at];

		mdd.song.edit.TakesPreset.kitting(Part.Dac, kit, hits, played, 0).apply(song);
		final once = song.instruments.length;

		mdd.song.edit.TakesPreset.kitting(Part.Dac, kit, hits, played, 1).apply(song);
		final twice = song.instruments.length;

		var sounding = 0;
		for (pitch in 0...128) if (song.drumAt(pitch) >= 0) sounding++;

		says("a piece holds nothing it has not loaded", before == 0,
			"a new song holds " + before + " presets with " + library.count() + " installed");

		says("and a kit arrives whole, once", once == hits.length && twice == once && sounding > 1,
			kit + " copied in as " + once + " presets, " + twice + " after loading it again, and "
			+ sounding + " keys sound");

		final lead = library.instruments[0][0];
		final take = mdd.song.edit.TakesPreset.adopting(Part.Fm1, lead, null);

		take.apply(song);
		final copied = song.instruments.length;

		take.revert(song);
		take.apply(song);

		says("and a preset loaded twice is one copy", copied == once + 1
			&& song.instruments.length == copied
			&& song.instrumentAt(song.rack[Part.Fm1.index()]).from == lead.id,
			"loading " + lead.name + ", undoing it and doing it again leaves " + song.instruments.length
			+ " presets, the last of them naming it as where it came from");
	}

	/**
		A new piece opens with every channel playing something out of the bank that ships, and
		carries those eleven presets and nothing else.
	**/
	static function opened():Void {
		final library = Library.embedded();
		final song = mdd.app.Session.empty(library);
		final shown:Array<String> = [];

		var silent = 0;

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final held = song.instrumentAt(song.rack[index]);

			if (held == null) {
				silent++;
				continue;
			}

			if (!Library.kin(held.kind, part)) silent++;
			if (index < 3 || part.noise()) shown.push(part.name() + " " + held.name);
		}

		says("a new piece opens with a channel playing on each part", silent == 0,
			silent + " parts with nothing to play; " + shown.join(", "));

		final at = library.names.indexOf(Library.STARTERS);
		final bank:Array<String> = [];

		for (held in (at < 0 ? [] : library.instruments[at])) bank.push(held.name);

		says("and the bank it opens with is the one that ships", bank.length == 131
			&& bank.indexOf("Lead guitar") >= 0 && bank.indexOf("Bounce bass") < 0,
			bank.length + " presets in " + Library.STARTERS
			+ ", named for what they are for");

		says("and it carries one preset for each part", song.instruments.length == Part.COUNT
			&& mdd.format.Needed.of(song).instruments.length == Part.COUNT,
			song.instruments.length + " presets in a new piece with " + library.count() + " installed");
	}

	/**
		How alike two presets are is what the browser sorts by and shows a percentage of, so one
		parameter moved has to cost one parameter's worth rather than the whole score.
	**/
	static function likened():Void {
		final one = patched("Lead");
		final same = patched("Lead");

		says("a preset is wholly like itself", one.likeness(same) == 1,
			"a copy scores " + Math.round(one.likeness(same) * 100) + " per cent");

		final nudged = patched("Lead");
		nudged.patch.totalLevel[0] += 4;

		final turned = patched("Lead");
		turned.patch.algorithm = turned.patch.algorithm == 0 ? 1 : 0;

		final nearly = Math.round(one.likeness(nudged) * 1000) / 10;
		final wired = Math.round(one.likeness(turned) * 1000) / 10;

		says("and one field moved costs one field", nearly > 99 && nearly < 100
			&& wired < nearly && wired > 90,
			"a total level four steps away scores " + nearly
			+ " per cent and another algorithm " + wired);

		final other = patched("Lead");

		for (slot in 0...mdd.song.Patch.SLOTS) {
			for (row in 0...mdd.song.Patch.ROWS) {
				other.patch.writes(slot, row, mdd.song.Patch.mostOf(row)
					- one.patch.reads(slot, row));
			}
		}

		final apart = Math.round(one.likeness(other) * 100);

		says("and a patch turned inside out scores low", apart < 40,
			"every operator field at the far end of its range scores " + apart + " per cent");

		final square = enveloped("Blip", Part.Psg1);

		says("and another kind of part scores nought", one.likeness(square) == 0
			&& square.likeness(one) == 0,
			"an FM patch against a square envelope scores 0 per cent either way");

		final other = enveloped("Blip", Part.Psg1);
		other.envelope.steps[0] = 15 - other.envelope.steps[0];

		final near = Math.round(square.likeness(other) * 1000) / 10;

		says("and an envelope counts a step as a step", near > 80 && near < 95,
			"one step of fifteen moved the whole way scores " + near + " per cent");

		mdd.host.Paths.clear(Gate.root + "/export/gate/likened");
	}

	/**
		A folder holding one patch under several names offers it once, and lifting a piece's
		patches writes none the library already has.

		Lifting wrote every preset a piece carried, and a piece carried the whole library, so a
		reader's folder filled with the shipped banks under names like `Bass 7 2` that say nothing
		about what they play. Reading it back listed each of them beside the patch it was a copy
		of.
	**/
	static function echoed(where:String):Void {
		mdd.host.Paths.clear(where);
		mdd.host.Paths.make(where);

		final made = patched("Lead");
		final folder = where + "/presets";

		mdd.host.Paths.make(folder + "/FM");

		for (name in ["Lead", "Lead 2", "Lead 3", "Lead 4"]) {
			sys.io.File.saveBytes(folder + "/FM/" + name + Library.PATCH,
				mdd.format.Tfi.write(made.patch));
		}

		final other = patched("Other");
		other.patch.feedback = 1;

		sys.io.File.saveBytes(folder + "/FM/Other" + Library.PATCH,
			mdd.format.Tfi.write(other.patch));

		final library = new Library();
		final read = library.within(folder, SAVED);

		final at = library.names.indexOf(SAVED);
		final shown:Array<String> = [];

		for (one in (at < 0 ? [] : library.instruments[at])) shown.push(one.name);

		says("one patch under several names is offered once", read == 2
			&& shown.join(", ") == "Lead, Other",
			"five files holding two patches read as " + read + ": " + shown.join(", ")
			+ ", so the name a reader gave it first is the one that stays");

		final song = new Song();
		final files = new mdd.app.Files(new mdd.app.Session(song));

		files.presetsAt = folder;
		files.savedInto = SAVED;
		files.library = library;

		final mine = patched("Lead");
		final theirs = other.copy();

		mine.name = "Lead Of Mine";
		theirs.name = "Theirs Renamed";

		for (one in [mine, theirs]) {
			one.patch.ams = 0;
			one.patch.pms = 0;

			for (slot in 0...mdd.song.Patch.SLOTS) one.patch.tremolo[slot] = false;
		}

		song.instrument(mine);
		song.instrument(theirs);

		final lifted = files.liftsPatches();

		says("and lifting writes none the library has", lifted == 0,
			lifted + " written out of two patches the library already offers");

		mdd.host.Paths.clear(where);
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
		A preset is what it sounds like rather than what it is called. Two presets differing in their
		sound differ in identity, two sounding the same are the same preset whatever each is called,
		tagged, drawn as or loaded on, and a channel edited in a piece is no longer the preset it
		started as, which is what lets a project carry its own and a reader keep theirs.
	**/
	/**
		A project holding a release rate past the four bits the chip has opens holding the most they
		carry, which is what an editor that let one through left behind.
	**/
	static function released():Void {
		final saved = new mdd.format.Json();
		final loud = patched("Loud release");

		loud.patch.release[1] = 31;
		Project.wroteInstrument(saved, loud);

		final loaded = Project.readInstrument(mdd.format.Json.parse(saved.toString()));

		says("a release rate reads as the chip's", loaded.patch.release[1] == 15,
			"a project holding a release rate of 31 opens holding " + loaded.patch.release[1]
			+ ", the most four bits carry");
	}

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

		two.tags.push("soft");
		final tagged = two.identifies(null);

		two.icon = one.icon + 1;
		final iconed = two.identifies(null);

		two.kind = Part.Fm4;
		final moved = two.identifies(null);

		says("an identity is what the preset sounds like", alike && level != one.id
			&& named == one.id && tagged == one.id && iconed == one.id && moved == one.id,
			"two presets written the same way answer " + one.id.substr(0, 8) + ", a total level answers "
			+ level.substr(0, 8) + ", and a name, a tag, an icon and another FM channel answer the same");

		final pulse = new Instrument("Pulse", Part.Psg2);
		for (step in [15, 9, 4, 0]) pulse.envelope.steps.push(step);

		pulse.envelope.loop = 2;
		pulse.envelope.speed = 3;
		pulse.envelope.noise = 5;

		final written = new haxe.io.BytesBuffer();
		for (byte in [1, 1, 4, 15, 9, 4, 0, 3, 0, 3, 5]) written.addByte(byte);

		final expected = haxe.crypto.Md5.make(written.getBytes()).toHex();
		final worked = pulse.identifies(null);

		says("and it is the MD5 of the bytes the notes lay out", worked == expected,
			"a square envelope of four steps answers " + worked + ", the MD5 of its eleven bytes");

		final stars = new mdd.app.Favourites();
		final installed = new Library();
		final kept = patched("Kept");

		installed.adds(SAVED, kept, null, false);
		kept.identifies(null);

		final former = mdd.app.Formerly.identity(kept, null);
		stars.favour(former, true);

		final carried = mdd.app.Formerly.stars(stars, installed);

		says("and a star on a former identity moves across", carried == 1 && stars.favours(kept.id)
			&& !stars.favours(former) && stars.count() == 1,
			carried + " star moved from " + former.substr(0, 8) + " to " + kept.id.substr(0, 8));

		final piece = new Song("formerly");
		final channel = piece.instrument(patched("Kept"));

		channel.patch.feedback = 1;
		channel.identifies(null);
		channel.from = former;

		final pointed = mdd.app.Formerly.origins(piece, installed);

		says("and so does where a channel came from", pointed == 1 && channel.from == kept.id,
			pointed + " channel now names " + channel.from.substr(0, 8) + " as where it came from");

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

		final library = new Library();
		library.reads(Library.saved(patched("Bass"), null), true, SAVED);

		final song = new Song("carrying");
		final session = new mdd.app.Session(song);

		session.library = library;
		mdd.song.edit.TakesPreset.adopting(Part.Fm1, library.instruments[0][0], null).apply(song);

		final own = song.instrumentAt(song.rack[Part.Fm1.index()]);
		final second = song.instrument(patched("Bass"));

		own.patch.feedback = 6;
		second.from = one.id;

		final origin = session.loadedFrom(own);

		says("a channel goes back to the installed preset", origin == library.instruments[0][0]
			&& origin.patch.feedback == 5 && own.from == one.id,
			"a channel edited to a feedback of 6 names " + own.from.substr(0, 8) + " as where it came"
			+ " from, and that is the library's own at " + (origin == null ? -1 : origin.patch.feedback)
			+ " rather than another copy the piece carries");
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

		final records = Gate.library();
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
		var inside = 0;
		var banks = 0;

		for (name in haxe.Resource.listNames()) {
			if (name.length <= 5 || name.substr(0, 5) != "bank.") continue;

			inside += haxe.Resource.getBytes(name).length;
			banks++;
		}

		built = inside + shippedBytes(root + "/export/bin/presets");

		final compiled = Library.embedded();

		says("every shipped preset comes across", carried == documents.count()
			&& documents.count() > 0 && missing == "",
			carried + " of " + documents.count() + " presets are the same preset as records"
			+ (missing == "" ? "" : ", missing " + missing));

		says("and only the starting bank is compiled in", compiled.names.length == 1
			&& compiled.names[0] == Library.STARTERS && compiled.count() == 131,
			compiled.count() + " presets in " + compiled.names.join(", ") + " inside the program, "
			+ inside + " bytes, and every other bank beside it");

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
		@param where A folder.
		@return How many bytes the files in it and every folder below it hold.
	**/
	static function shippedBytes(where:String):Int {
		if (!sys.FileSystem.exists(where)) return 0;

		var many = 0;

		for (name in sys.FileSystem.readDirectory(where)) {
			final path = where + "/" + name;
			many += sys.FileSystem.isDirectory(path) ? shippedBytes(path) : sys.FileSystem.stat(path).size;
		}

		return many;
	}

	/**
		The banks that ship beside the application are written into a presets folder once: a bank
		deleted there stays deleted, a newer build's bank replaces a copy nobody changed, and one a
		reader changed is left as it is.
	**/
	static function planted(where:String):Void {
		mdd.host.Paths.clear(where);

		final from = where + "/shipped";
		final into = where + "/presets";

		mdd.host.Paths.make(from + "/FM");
		mdd.host.Paths.make(from + "/DAC");

		sys.io.File.saveBytes(from + "/FM/Game" + Library.BANK,
			mdd.format.Preset.write("Game", [patched("Game")], [null]));
		sys.io.File.saveBytes(from + "/FM/Other" + Library.BANK,
			mdd.format.Preset.write("Other", [patched("Other")], [null]));
		sys.io.File.saveBytes(from + "/DAC/Kit" + Library.BANK,
			mdd.format.Preset.write("Kit", [new Instrument("Kick", Part.Dac)], [sampled("Kick")]));

		final first = mdd.app.ShippedBanks.plants(from, into, "");
		final planted = mdd.app.ShippedBanks.planted(first, into);

		final written = sys.FileSystem.exists(into + "/FM/Game" + Library.BANK)
			&& sys.FileSystem.exists(into + "/DAC/Kit" + Library.BANK) && planted.length == 3;

		sys.FileSystem.deleteFile(into + "/FM/Game" + Library.BANK);
		sys.io.File.saveBytes(into + "/FM/Other" + Library.BANK,
			mdd.format.Preset.write("Other", [patched("Other")], [null], ["Mine"]));

		final changed = patched("Kick");
		sys.io.File.saveBytes(from + "/FM/Other" + Library.BANK,
			mdd.format.Preset.write("Other", [patched("Other"), changed], [null, null]));

		final hit = new Instrument("Snare", Part.Dac);
		sys.io.File.saveBytes(from + "/DAC/Kit" + Library.BANK,
			mdd.format.Preset.write("Kit", [new Instrument("Kick", Part.Dac), hit],
			[sampled("Kick"), sampled("Snare")]));

		final second = mdd.app.ShippedBanks.plants(from, into, first);

		final other = mdd.format.Preset.read(sys.io.File.getBytes(into + "/FM/Other" + Library.BANK));
		final kit = mdd.format.Preset.read(sys.io.File.getBytes(into + "/DAC/Kit" + Library.BANK));

		final third = mdd.app.ShippedBanks.plants(from, where + "/elsewhere", second);

		says("the banks that ship are written into the presets folder once", written
			&& !sys.FileSystem.exists(into + "/FM/Game" + Library.BANK)
			&& other != null && other.presets.length == 1 && other.tags.join(",") == "Mine"
			&& kit != null && kit.presets.length == 2
			&& sys.FileSystem.exists(where + "/elsewhere/FM/Game" + Library.BANK),
			"3 written; a deleted one stayed deleted, one the reader tagged kept its tag over a newer"
			+ " build's, the kit nobody changed took the newer build's " + (kit == null ? 0
			: kit.presets.length) + " hits, and another presets folder was given all three");

		mdd.host.Paths.clear(where);
	}

	/**
		Loading a preset into a channel takes a copy of it, so playing with the channel leaves the
		preset as it was written and choosing it again puts the channel back. That is what a piece
		needs to carry its own presets: the copy says which preset it came from, and the preset is
		in the piece, so neither needs a reader's own folder.
	**/
	/**
		Copying, pasting and resetting a channel's preset reach every kind of channel, as steps on
		the undo stack: a square's pastes onto another square and onto no other kind, undo puts the
		other square back, a reset keeps the name and nothing else, and the sample channel's
		recording comes across with it.
	**/
	static function rackCopied():Void {
		final session = new mdd.app.Session(mdd.app.Session.empty(Library.embedded()));
		final song = session.song;
		final first = song.instrumentAt(song.rack[Part.Psg1.index()]);
		final before = song.instrumentAt(song.rack[Part.Psg2.index()]);

		if (first == null || before == null || Library.sounds(first, before)) {
			says("every channel's preset copies and pastes", false, "a new piece's first two squares"
				+ " play the same preset, so a paste between them shows nothing");
			return;
		}

		session.copiesPreset(Part.Psg1);

		final refused = !session.pastes(Part.Fm1) && !session.pastes(Part.Noise) && session.pastes(Part.Psg2);

		session.pastesPreset(Part.Psg2);
		final pasted = Library.sounds(first, song.instrumentAt(song.rack[Part.Psg2.index()]));

		session.undo();
		final undone = song.instrumentAt(song.rack[Part.Psg2.index()]) == before;

		session.resetsPreset(Part.Psg2);
		final fresh = song.instrumentAt(song.rack[Part.Psg2.index()]);
		final reset = fresh != null && fresh.name == before.name && fresh.envelope != null
			&& fresh.envelope.steps.length == 0;

		final samples = song.samples.length;
		final kick = song.instrumentAt(song.rack[Part.Dac.index()]);
		final recording = kick == null ? null : song.sampleAt(kick.sample);

		session.copiesPreset(Part.Dac);
		session.pastesPreset(Part.Dac);

		final taken = song.instrumentAt(song.rack[Part.Dac.index()]);
		final carried = song.sampleAt(taken == null ? -1 : taken.sample);
		final whole = recording != null && carried != null && carried != recording
			&& carried.length() == recording.length() && song.samples.length == samples + 1;

		says("every channel's preset copies and pastes", refused && pasted && undone && reset && whole,
			"PSG1's " + first.name + " pastes onto PSG2 " + (pasted ? "whole" : "changed") + " and onto"
			+ " neither FM1 nor NOISE, undo puts " + before.name + " back " + (undone ? "" : "not ")
			+ "as it was, a reset keeps the name with an empty envelope, and the sample channel's "
			+ (recording == null ? "missing recording" : recording.length() + " byte recording")
			+ " pastes as " + (whole ? "a copy of its own" : "something else"));
	}

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
		A preset swapped out of a channel stays the piece's own until the piece is saved by hand and
		closed. The browser keeps offering it and a save on its own keeps writing it; a save by hand
		leaves it out of the file but it is still offered until the piece closes. A copy of an
		installed preset that was never played with is not kept, because the library still has it,
		and one that was played with is.
	**/
	static function spared(where:String):Void {
		mdd.host.Paths.clear(where);
		mdd.host.Paths.make(where);

		final song = new Song("spared");
		final own = song.instrument(patched("Own"));
		final other = song.instrument(patched("Other"));

		song.rack[Part.Fm1.index()] = song.instruments.indexOf(own);
		song.rack[Part.Fm2.index()] = song.instruments.indexOf(other);

		final session = new mdd.app.Session(song);
		final files = new mdd.app.Files(session);
		final named = where + "/spared." + mdd.Config.SUFFIX;

		files.backupRoom = 0;
		files.save(named);

		final plain = patched("Tried plain");
		final edited = patched("Tried edited");
		final last = patched("Tried last");
		final after = patched("Tried after");

		for (one in [plain, edited, last, after]) one.identifies(null);

		mdd.song.edit.TakesPreset.adopting(Part.Fm1, plain, null).apply(song);
		final tried = song.instrumentAt(song.rack[Part.Fm1.index()]);

		says("a preset swapped out of a channel stays", offers(session, own),
			"Fm1 plays " + (tried == null ? "nothing" : tried.name) + " and the piece still offers "
			+ own.name + " as its own");

		mdd.song.edit.TakesPreset.adopting(Part.Fm1, edited, null).apply(song);
		final played = song.instrumentAt(song.rack[Part.Fm1.index()]);

		says("and a copy nobody played with does not", tried != null && !offers(session, tried),
			"swapped out as it was loaded, " + plain.name + " is left to the library");

		if (tried == null || played == null || played.patch == null) return;

		played.patch.feedback = played.patch.feedback == 7 ? 1 : 7;
		mdd.song.edit.TakesPreset.adopting(Part.Fm1, last, null).apply(song);

		says("and one that was played with does", offers(session, played),
			"swapped out at a feedback of " + played.patch.feedback + ", " + played.name
			+ " is still offered");

		final kept = files.keep();
		final autosaved = names(named);

		says("and a save on its own writes them", kept && autosaved.indexOf(own.name) >= 0
			&& autosaved.indexOf(played.name) >= 0 && autosaved.indexOf(plain.name) < 0,
			"the file carries " + autosaved.join(", "));

		files.save(named);
		final saved = names(named);

		says("a save by hand leaves them out", saved.indexOf(own.name) < 0
			&& saved.indexOf(played.name) < 0 && offers(session, own) && offers(session, played),
			"the file carries " + saved.join(", ") + ", and the open piece still offers "
			+ own.name + " and " + played.name);

		mdd.song.edit.TakesPreset.adopting(Part.Fm2, after, null).apply(song);

		final again = files.keep();
		final later = names(named);

		says("and later ones do not write them back", again
			&& later.indexOf(other.name) >= 0 && later.indexOf(own.name) < 0
			&& later.indexOf(played.name) < 0,
			"swapping Fm2 out and saving on its own carries " + later.join(", "));

		other.name = "Other renamed";

		final noticed = files.unsaved();
		final renamed = files.keep() ? names(named) : [];

		says("and renaming one is work to save", noticed && renamed.indexOf(other.name) >= 0,
			"renamed while nothing plays it, it is unsaved work and reads " + other.name
			+ " in the file");

		final reopened = Project.open(named);
		final next = new mdd.app.Session(reopened);
		final spare = found(reopened, other.name);

		says("and closing the piece lets them go", spare != null && offers(next, spare)
			&& found(reopened, own.name) == null,
			"opened again, it offers " + other.name + " from its file and holds no " + own.name);

		mdd.host.Paths.clear(where);
	}

	/**
		@param session A session.
		@param held A preset its piece holds.
		@return Whether the browser offers it as the piece's own: the piece plays it, or keeps it.
	**/
	static function offers(session:mdd.app.Session, held:Instrument):Bool {
		final song = session.song;
		final played = mdd.format.Needed.of(song);
		final at = song.instruments.indexOf(held);

		return at >= 0 && (played.instrument(at) >= 0 || session.spares(played, false)[at]);
	}

	/**
		@param named A project file.
		@return The names of the presets it carries, in its order.
	**/
	static function names(named:String):Array<String> {
		final out:Array<String> = [];
		for (held in Project.open(named).instruments) out.push(held.name);

		return out;
	}

	/**
		@param song A piece.
		@param name A preset's name.
		@return The first preset of that name it holds, or null.
	**/
	static function found(song:Song, name:String):Null<Instrument> {
		for (held in song.instruments) if (held.name == name) return held;

		return null;
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

		sys.io.File.saveBytes(where + "/Pad" + Library.RECORDS,
			mdd.format.Preset.write("", [patched("Pad")], [null]));

		sys.io.File.saveBytes(where + "/Hits" + Library.BANK,
			mdd.format.Preset.write("Metal", [new Instrument("Kick", Part.Dac)],
			[sampled("kick")]));

		final files = new mdd.app.Files(new mdd.app.Session(new Song()));
		files.presetsAt = where;

		final moved = files.sortsPresets();

		final landed = sys.FileSystem.exists(where + "/FM/Lead.json")
			&& sys.FileSystem.exists(where + "/FM/Slap.tfi")
			&& sys.FileSystem.exists(where + "/FM/Bass/Sub.json")
			&& sys.FileSystem.exists(where + "/PSG/Beeps.json")
			&& sys.FileSystem.exists(where + "/NOISE/Hits.json")
			&& sys.FileSystem.exists(where + "/NOISE/Kit.json")
			&& sys.FileSystem.exists(where + "/FM/Pad" + Library.RECORDS)
			&& sys.FileSystem.exists(where + "/DAC/Hits" + Library.BANK);

		final stayed = sys.FileSystem.exists(where + "/Both.json")
			&& !sys.FileSystem.exists(where + "/Lead.json");

		says("what was there is sorted by family", moved == 8 && landed && stayed,
			moved + " files moved, each under the folder its family stands in, the subfolder they"
			+ " were in kept, a preset file and a bank of one family with them, and the document"
			+ " carrying two families left where it is");

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
		A preset moved into a subfolder moves to that bank once the folder is read again, and a
		piece that plays it goes on playing it: the piece holds its own copy, and still knows it by
		identity where it now sits.
	**/
	static function moved(where:String):Void {
		mdd.host.Paths.clear(where);
		mdd.host.Paths.make(where);

		final keys = patched("Keys");
		keys.patch.feedback = 2;

		sys.io.File.saveContent(where + "/Lead.json", Library.saved(patched("Lead"), null));
		sys.io.File.saveContent(where + "/Keys.json", Library.saved(keys, null));

		final library = new Library();
		library.within(where, SAVED);

		final song = new Song();
		var lead = library.instruments[0][0];

		for (held in library.instruments[0]) if (held.name == "Lead") lead = held;

		mdd.song.edit.TakesPreset.adopting(Part.Fm1, lead, null).apply(song);

		sys.FileSystem.createDirectory(where + "/Leads");
		sys.FileSystem.rename(where + "/Lead.json", where + "/Leads/Lead.json");
		sys.FileSystem.createDirectory(where + "/Keys");
		sys.FileSystem.rename(where + "/Keys.json", where + "/Keys/Keys.json");

		library.forgets();
		library.within(where, SAVED);

		final saved = shelved(library, SAVED);
		final leads = shelved(library, "Leads");
		final keyed = shelved(library, "Keys");
		final playing = song.instrumentAt(song.rack[Part.Fm1.index()]);

		says("a preset moved into a subfolder moves", leads == "Lead" && keyed == "Keys"
			&& saved == "" && playing != null && library.offering(lead) == "Leads"
			&& playing.from == lead.id,
			SAVED + " holds '" + saved + "', Leads holds " + leads + ", Keys holds " + keyed
			+ ", and the piece still plays its copy of Lead, found by identity in " + library.offering(lead));
	}

	/**
		@param library A library.
		@param name One of its banks.
		@return The names of the presets in it, in order.
	**/
	static function shelved(library:Library, name:String):String {
		final at = library.names.indexOf(name);
		final out:Array<String> = [];

		for (held in (at < 0 ? [] : library.instruments[at])) out.push(held.name);

		return out.join(", ");
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
		final kick = sampled("kick");

		lead.identifies(null);

		files.chooses("", [lead], [null]);
		final wrotePatch = files.writesPresetTfi(where + "/Glass Lead");

		files.chooses("", [drum], [kick]);
		final wroteWave = files.writesPresetWav(where + "/Kick");

		files.chooses("Kit", [lead, hit, drum], [null, null, kick]);
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
		final installed = new Library();

		reading.presetsAt = where + "/read";
		reading.savedInto = SAVED;
		reading.library = installed;
		reading.readPresets(wroteBank);

		final at = installed.names.indexOf("Kit");
		final recordings = at < 0 ? 0 : installed.samples[at].filter(function(one:Null<Sample>):Bool
			return one != null).length;

		says("and a bank reads back into the library, not the piece",
			shelved(installed, "Kit") == "Glass Lead, Blip, Kick" && recordings == 1
			&& other.instruments.length == 0,
			shelved(installed, "Kit") + "; " + recordings + " recording; the open piece holds "
			+ other.instruments.length);

		var home:Null<Instrument> = null;

		for (held in (at < 0 ? [] : installed.instruments[at])) if (held.id == lead.id) home = held;

		says("and it is the same preset it was written from", home != null
			&& home.name == "Glass Lead" && mdd.format.Tfi.same(lead.patch, home.patch),
			"identity " + lead.id + " on both sides");

		mdd.host.Paths.clear(where);
	}

	/**
		A kit converted in the application is written into the converter's own folder as records,
		and it reads straight back as one bank with its recordings.
	**/
	static function fitted(where:String):Void {
		mdd.host.Paths.clear(where);
		mdd.host.Paths.make(where);

		final song = new Song();
		final files = new mdd.app.Files(new mdd.app.Session(song));
		final library = new Library();

		files.presetsAt = where;
		files.savedInto = SAVED;
		files.library = library;

		final kit = new mdd.format.Kit();

		kit.name = "Metal";
		kit.tags = "Drums, Metal";

		for (name in ["Kick", "Snare", "Hat"]) {
			final slot = new mdd.format.Slot("", name);

			slot.made = sampled(name);
			slot.icon = mdd.Icon.NAMES.indexOf("drumkit");

			kit.slots.push(slot);
		}

		final named = files.writeKit(kit);
		final under = mdd.app.Files.name(haxe.io.Path.directory(named));

		final fresh = new Library();
		fresh.within(where, SAVED);

		final at = fresh.names.indexOf("Metal");
		final held:Array<Instrument> = at < 0 ? [] : fresh.instruments[at];
		final shown:Array<String> = [];

		for (one in held) shown.push(one.name);

		final hit = at < 0 || fresh.samples[at].length == 0 ? null : fresh.samples[at][0];

		says("a converted kit is written as records", under == "DAC"
			&& StringTools.endsWith(named, Library.BANK) && shown.join(", ") == "Kick, Snare, Hat"
			&& hit != null && hit.length() == sampled("Kick").length(),
			mdd.app.Files.name(named) + " under " + under + ", holding " + shown.join(", ")
			+ ", each of " + (hit == null ? 0 : hit.length()) + " bytes");

		says("and the library offers it straight away",
			shelved(library, "Metal") == "Kick, Snare, Hat" && song.instruments.length == 0,
			shelved(library, "Metal") + "; the open piece holds " + song.instruments.length);

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
			== "Glass Lead 5 2/5 Lead+Bright, Glass Lead 1 2/5 Lead+Bright"
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

		if (many > 512) throw "a fixture that cannot give every preset its own sound";

		mdd.host.Paths.make(folder + "/FM/Leads");
		mdd.host.Paths.make(folder + "/DAC");

		for (index in 0...many) {
			final one = patched("Patch " + index);

			one.patch.feedback = index & 7;
			one.patch.totalLevel[0] = index & 127;
			one.patch.keyScale[2] = (index >> 7) & 3;

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
		A preset read out of the presets folder is dated by its file the first time it is seen, and
		keeps that date through a rename, new tags and a move to another folder, because the date is
		kept by what it sounds like. The dates read back as they were written.
	**/
	static function dated(where:String):Void {
		mdd.host.Paths.clear(where);
		mdd.host.Paths.make(where + "/FM");

		final made = patched("Dated");
		final path = where + "/FM/Dated" + Library.RECORDS;

		sys.io.File.saveBytes(path, mdd.format.Preset.write("", [made], [null]));

		final written = sys.FileSystem.stat(path).mtime.getTime() / 1000;
		final library = new Library();
		library.within(where, SAVED);

		final added = new mdd.app.Added();
		final first = added.sees(library, written + 1000000);
		final id = library.instruments[0][0].id;

		sys.FileSystem.deleteFile(path);
		mdd.host.Paths.make(where + "/FM/Moved");

		final renamed = made.copy();
		renamed.name = "Renamed";
		renamed.tags.push("Moved");

		sys.io.File.saveBytes(where + "/FM/Moved/Renamed" + Library.RECORDS,
			mdd.format.Preset.write("", [renamed], [null]));

		library.forgets();
		library.within(where, SAVED);

		final again = added.sees(library, written + 2000000);
		final back = new mdd.app.Added();
		back.reads(added.spelt());

		says("a preset is dated by its file, once", first == 1 && again == 0
			&& Math.abs(added.when(id) - written) < 2 && library.instruments[0][0].id == id
			&& back.when(id) == added.when(id),
			"dated " + Math.round(added.when(id)) + " against a file written at " + Math.round(written)
			+ ", and still after a rename, a tag and a move, which gave " + again + " new dates");

		mdd.host.Paths.clear(where);
	}

	/**
		A preset in the reader's folder is renamed, retagged, moved and deleted by changing its
		file, a patch file that has to carry a tag becoming a preset file, and a category is made,
		tagged and deleted as a folder. Nothing deleted is erased: it is in the backups.
	**/
	static function organised(where:String):Void {
		mdd.host.Paths.clear(where);

		final root = where + "/presets";
		final bin = where + "/bin";

		mdd.host.Paths.make(root + "/FM/Leads");
		mdd.host.Paths.make(root + "/FM/Empty");

		final pads = patched("Warm");
		final wide = patched("Wide");
		wide.patch.feedback = 2;

		sys.io.File.saveBytes(root + "/FM/Lead" + Library.RECORDS,
			mdd.format.Preset.write("", [patched("Lead")], [null]));
		sys.io.File.saveBytes(root + "/FM/Slap" + Library.PATCH, mdd.format.Tfi.write(patched("Slap").patch));
		sys.io.File.saveBytes(root + "/FM/Pads" + Library.BANK,
			mdd.format.Preset.write("Pads", [pads, wide], [null, null], ["Soft"]));
		sys.io.File.saveBytes(root + "/FM/Leads/Saw" + Library.RECORDS,
			mdd.format.Preset.write("", [patched("Saw")], [null]));
		sys.io.File.saveContent(root + "/FM/Leads/" + Library.TAGS, "Bright\nLead\n");

		final library = new Library();
		library.within(root, SAVED);

		final empty = library.folderOf("FM", "Empty");
		final leads = library.names.indexOf("Leads");
		final banked = library.names.indexOf("Pads");

		says("an empty folder is a category, and a folder and a bank carry tags", empty != ""
			&& leads >= 0 && library.tagsOf(leads).join(",") == "Bright,Lead" && banked >= 0
			&& library.tagsOf(banked).join(",") == "Soft",
			"Empty is read from '" + mdd.app.Files.name(empty) + "', Leads carries "
			+ (leads < 0 ? "" : library.tagsOf(leads).join(", ")) + " and Pads carries "
			+ (banked < 0 ? "" : library.tagsOf(banked).join(", ")));

		final folder = new mdd.app.PresetFolder(root, bin);

		final lead = placed(library, patched("Lead"));
		final renamed = folder.renames(library, lead >> 16, lead & 0xFFFF, "Lead Two");

		var slap = -1;

		for (at in 0...library.names.length) {
			for (which in 0...library.instruments[at].length) {
				if (library.instruments[at][which].name == "Slap") slap = (at << 16) | which;
			}
		}

		final tagged = folder.retags(library, slap >> 16, slap & 0xFFFF, ["Slap", "Funk"]);

		final warm = placed(library, pads);
		final dropped = folder.deletes(library, warm >> 16, warm & 0xFFFF);

		library.forgets();
		library.within(root, SAVED);

		final spread = placed(library, wide);
		final moved = folder.moves(library, spread >> 16, spread & 0xFFFF, empty);

		final keys = folder.makes("FM", "Keys");
		final kept = keys != "" && folder.tagsCategory(keys, ["Keys", "Soft"]);
		final gone = folder.deletesCategory(keys);

		library.forgets();
		library.within(root, SAVED);

		final binned = sys.FileSystem.exists(bin) ? sys.FileSystem.readDirectory(bin).length : 0;
		final slapped = library.instruments[library.names.indexOf(SAVED)].filter(function(one:Instrument):Bool
			return one.name == "Slap");

		says("a preset in the folder is changed through its file", renamed && tagged && dropped
			&& moved && sys.FileSystem.exists(root + "/FM/Lead Two" + Library.RECORDS)
			&& !sys.FileSystem.exists(root + "/FM/Lead" + Library.RECORDS)
			&& sys.FileSystem.exists(root + "/FM/Slap" + Library.RECORDS)
			&& !sys.FileSystem.exists(root + "/FM/Slap" + Library.PATCH)
			&& slapped.length == 1 && slapped[0].tags.join(",") == "Slap,Funk"
			&& shelved(library, "Empty") == "Wide" && !sys.FileSystem.exists(root + "/FM/Pads" + Library.BANK),
			"renamed to Lead Two, a patch file retagged into a preset file, Warm deleted and Wide moved"
			+ " into Empty, which left Pads empty and moved it out" + (renamed && tagged && dropped && moved ? ""
			: " (renamed " + renamed + ", tagged " + tagged + ", dropped " + dropped + ", moved " + moved + ")")
			+ "; Empty holds '" + shelved(library, "Empty") + "', Slap carries "
			+ (slapped.length == 0 ? "nothing" : slapped[0].tags.join(",")));

		says("and a category is made, tagged and deleted", keys != "" && kept && gone
			&& !sys.FileSystem.exists(keys) && binned == 3,
			"Keys made and tagged, then deleted, and the backups hold " + binned + ": the patch file,"
			+ " Pads once it was empty, and Keys");

		final cache = where + "/presets.cache";
		library.caches(cache, "stamp");

		final back = new Library();
		back.cached(cache, "stamp");

		final at = back.names.indexOf("Leads");
		final first = back.paths.length > 0 && back.paths[0].length > 0 ? back.paths[0][0] : "";

		says("and the cache keeps where each one lives", at >= 0 && back.tagsOf(at).join(",") == "Bright,Lead"
			&& back.folders.join("|") == library.folders.join("|")
			&& first == library.paths[0][0] && first != "",
			back.folders.length + " folders and every preset's file read back, Leads still tagged "
			+ (at < 0 ? "" : back.tagsOf(at).join(", ")));

		final old = mdd.format.Preset.write("Old", [patched("Old")], [null]);
		final written = haxe.io.Bytes.alloc(old.length - 1);

		written.blit(0, haxe.io.Bytes.ofString(mdd.format.Preset.UNTAGGED), 0, 4);
		written.blit(4, old, 4, 5);
		written.blit(9, old, 10, old.length - 10);

		final read = mdd.format.Preset.read(written);

		says("and a bank file written before banks had tags still reads", read != null
			&& read.name == "Old" && read.presets.length == 1 && read.tags.length == 0,
			"an " + mdd.format.Preset.UNTAGGED + " file reads as " + (read == null ? "nothing"
			: read.presets.length + " preset in " + read.name));

		mdd.host.Paths.clear(where);
	}

	/**
		A preset file imported on its own goes into the Imported category of its family, and a bank
		holding presets the library already holds asks, then skips them or combines their tags.
	**/
	static function imported(where:String):Void {
		mdd.host.Paths.clear(where);

		final root = where + "/presets";
		mdd.host.Paths.make(root + "/FM");

		final known = patched("Known");
		known.tags.resize(0);
		known.tags.push("Mine");

		sys.io.File.saveBytes(root + "/FM/Known" + Library.RECORDS,
			mdd.format.Preset.write("", [known], [null]));

		final files = new mdd.app.Files(new mdd.app.Session(new Song()));
		final library = new Library();

		files.presetsAt = root;
		files.savedInto = SAVED;
		files.importedInto = "Imported";
		files.library = library;

		library.within(root, SAVED);

		final single = where + "/Single" + Library.RECORDS;
		sys.io.File.saveBytes(single, mdd.format.Preset.write("", [patched("Single")], [null]));
		files.readPresets(single);

		final arriving = patched("Known");
		arriving.tags.resize(0);
		arriving.tags.push("Theirs");

		final bank = where + "/Theirs" + Library.BANK;
		sys.io.File.saveBytes(bank, mdd.format.Preset.write("Theirs", [arriving, patched("New")], [null, null]));

		var asked = -1;
		files.onDuplicates = function(from:String, held:mdd.format.Banked, twins:Int):Void asked = twins;
		files.readPresets(bank);

		final outcomes:Array<String> = [];
		files.onImported = function(named:String, many:Int, single:Bool):Void
			outcomes.push(named + " " + many + " " + single);

		final skipped = files.imports(bank, mdd.format.Preset.read(sys.io.File.getBytes(bank)),
			mdd.app.Files.SKIP_DUPLICATES);
		final skippedHeld = mdd.format.Preset.read(sys.io.File.getBytes(skipped));

		final combined = files.imports(bank, mdd.format.Preset.read(sys.io.File.getBytes(bank)),
			mdd.app.Files.COMBINE_TAGS);
		final combinedHeld = mdd.format.Preset.read(sys.io.File.getBytes(combined));
		final mine = mdd.format.Preset.read(sys.io.File.getBytes(root + "/FM/Known" + Library.RECORDS));

		says("a preset imported alone goes into Imported", sys.FileSystem.exists(root + "/FM/Imported/Single"
			+ Library.RECORDS) && shelved(library, "Imported") == "Single",
			"Single landed in FM/Imported and the library offers it there");

		says("and a bank with presets already held asks first", asked == 1 && skippedHeld != null
			&& skippedHeld.presets.length == 1 && skippedHeld.presets[0].name == "New",
			asked + " already held, and skipping them wrote " + (skippedHeld == null ? 0
			: skippedHeld.presets.length) + " preset");

		final english = new mdd.ui.Translation();
		mdd.app.Languages.speak(english, "en-GB");

		final said = mdd.app.PresetImport.told(english, "Theirs", 2, false, root);
		final none = mdd.app.PresetImport.told(english, "Theirs", 0, false, root);
		final taken = mdd.app.PresetImport.argument(["--quiet", bank]);
		final exporting = mdd.app.PresetImport.argument(["--export=" + where + "/a.wav", bank]);

		says("and says what came of it, in a window or out of one", outcomes.join(", ")
			== "Theirs 1 false, Theirs 2 false" && said == "Bank Theirs was imported with 2 presets."
			&& StringTools.startsWith(none, "Nothing in Theirs was new") && taken == bank && exporting == "",
			"'" + said + "', and a bank file among the arguments is imported before a window opens"
			+ " unless an export was asked for");

		says("and combining gives both copies both tags", combinedHeld != null && mine != null
			&& both(combinedHeld.presets[0].tags) && both(mine.presets[0].tags),
			"the arriving copy carries " + (combinedHeld == null ? "" : combinedHeld.presets[0].tags.join(", "))
			+ " and the one already there " + (mine == null ? "" : mine.presets[0].tags.join(", ")));

		mdd.host.Paths.clear(where);
	}

	/**
		@param tags Some tags.
		@return Whether they are Mine and Theirs, in either order.
	**/
	static function both(tags:Array<String>):Bool {
		return tags.length == 2 && tags.indexOf("Mine") >= 0 && tags.indexOf("Theirs") >= 0;
	}

	/**
		@param library A library.
		@param preset A preset, whose identity is worked out here.
		@return Where the library holds it, as `Library.placeOf` answers.
	**/
	static function placed(library:Library, preset:Instrument):Int {
		return library.placeOf(preset.copy().identifies(null));
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

		var seed = 0;

		for (index in 0...name.length) {
			final code = name.charCodeAt(index);
			if (code != null) seed = seed * 31 + code;
		}

		patch.detune[3] = seed & 7;
		patch.multiple[3] = (seed >> 3) & 15;
		patch.keyScale[3] = (seed >> 7) & 3;

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

		envelope.steps.push(name.length & 15);

		envelope.turns(Envelope.LOOP, 4);
		envelope.turns(Envelope.SPEED, 3);
		if (kind.noise()) envelope.turns(Envelope.NOISE, 6);

		out.tags.push("Short");
		return out;
	}

	/**
		@param name What to call it, which also decides its bytes, so two hits of different names
			are two sounds rather than one recording under two names.
		@return A short sample with a loop point.
	**/
	static function sampled(name:String):Sample {
		final out = new Sample(name, 13000, 38);
		final bytes = new haxe.ds.Vector<Int>(700);

		var seed = 0;
		for (at in 0...name.length) seed += StringTools.fastCodeAt(name, at);

		for (at in 0...bytes.length) bytes[at] = (at * 13 + 5 + seed) & 0xFF;

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
