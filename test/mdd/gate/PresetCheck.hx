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

		final where = Gate.root + "/export/gate/presets";
		mdd.host.Paths.clear(where);
		mdd.host.Paths.make(where);

		folded(where);
		moved(where);
		written(where);

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

		final kit = "{\"name\": \"Drums\", \"presets\": []}";
		sys.io.File.saveContent(where + "/Drums.json", kit);

		final first = files.keepsPreset(patched("Drums"), null);
		final again = patched("Drums");
		again.patch.algorithm = 3;
		final second = files.keepsPreset(again, null);
		final third = files.keepsPreset(patched("Bell"), null);

		final kept = sys.io.File.getContent(where + "/Drums.json") == kit;
		final named = mdd.app.Files.name(first) + ", " + mdd.app.Files.name(second) + ", "
			+ mdd.app.Files.name(third);

		final at = library.names.indexOf(SAVED);
		final held:Array<Instrument> = at < 0 ? [] : library.instruments[at];
		final shown:Array<String> = [];

		for (one in held) shown.push(one.name + " " + one.patch.algorithm);

		final fresh = new Library();
		fresh.within(where, SAVED);

		final reread = fresh.names.indexOf(SAVED);
		final back = reread < 0 ? 0 : fresh.instruments[reread].length;

		says("a saved preset is written beside a bank", kept && named
			== "Drums 2.json, Drums 2.json, Bell.json" && shown.join(", ") == "Drums 3, Bell 7"
			&& back == 2, named + "; library holds " + shown.join(", ") + "; " + back
			+ " read back from the folder");
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
