package mdd.gate;

import mdd.format.Needed;
import mdd.format.Project;
import mdd.play.Sequencer;
import mdd.play.Stream;
import mdd.song.Instrument;
import mdd.song.Library;
import mdd.song.Part;
import mdd.song.Song;

@:unreflective

/**
	A file carries the piece, not the presets that were tried in it or offered beside it.

	What a file has to carry is what the piece plays, and the proof that the right thing was left
	out is that the register stream is the same afterwards.
**/
class ProjectCheck {
	static var failed:Int = 0;
	static var ran:Int = 0;

	static inline final SPAN = 44100 * 8;

	/**
		@param args The gate's arguments, unused.
		@return Nought where every case held.
	**/
	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  project");

		final where = Gate.root + "/export/gate/project";

		mdd.host.Paths.clear(where);
		mdd.host.Paths.make(where);

		carried(where);
		kitted(where);
		heard(where);
		older(where);

		mdd.host.Paths.clear(where);

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");
		Sys.println(failed == 0 ? "    passed" : "    failed");

		return failed == 0 ? 0 : 1;
	}

	/**
		A piece that has had preset after preset loaded into a channel is written as what it plays,
		and it sounds the same when it is read back.

		Each load copies a preset into the piece, so browsing leaves a copy behind for every preset
		tried. Writing those put a piece of twenty presets on disk as three hundred, and nothing in
		the music asked for any of them.
	**/
	static function carried(where:String):Void {
		final song = StreamCheck.written();
		final library = stocked();
		final shelf = library.names.indexOf("Shipped");

		final own = song.instruments.length;
		final part = Part.Fm2;
		var last:Null<Instrument> = null;

		for (index in 0...library.instruments[shelf].length) {
			final take = mdd.song.edit.TakesPreset.adopting(part, library.instruments[shelf][index], null);

			take.apply(song);
			last = song.instrumentAt(song.rack[part.index()]);
			take.revert(song);
		}

		final tried = song.instruments.length - own;

		final before = new Stream(262144);
		new Sequencer(song).emit(before, 0, SPAN);

		final named = where + "/carried.mdsyn";
		Project.save(song, named);

		final back = Project.open(named);
		final playing = Needed.of(song).instruments.length;

		var left = 0;
		for (held in back.instruments) if (last != null && held.name == last.name) left++;

		says("a file carries what the piece plays", back.instruments.length == playing
			&& playing <= own && tried == library.instruments[shelf].length && left == 0,
			song.instruments.length + " presets open, " + tried + " of them tried in a channel and"
			+ " let go, " + back.instruments.length + " written");

		var reaches = 0;

		for (held in back.instruments) {
			if (held.sample < 0) continue;
			if (back.sampleAt(held.sample) != null) reaches++;
		}

		says("and no recording it does not play", back.samples.length <= song.samples.length
			&& reaches > 0 && orphans(back) == 0,
			back.samples.length + " recordings written of " + song.samples.length
			+ ", every one of them played by " + reaches + " presets");

		final after = new Stream(262144);
		new Sequencer(back).emit(after, 0, SPAN);

		says("and it sounds the same", before.count > 0 && alike(before, after) == -2,
			before.count + " register writes over " + SPAN + " samples, and the file reads back "
			+ after.count + ", " + (alike(before, after) == -2 ? "every one the same"
			: "differing at " + alike(before, after)));
	}

	/**
		The kit behind a converter preset is written whole, because a hit is picked by note out of
		a bank rather than named by the note, and a kit taken out of the library arrives whole.
	**/
	static function kitted(where:String):Void {
		final song = StreamCheck.written();
		final library = stocked();
		final shelf = library.names.indexOf("Spare Kit");

		mdd.song.edit.TakesPreset.kitting(Part.Dac, "Spare Kit", library.instruments[shelf],
			library.samples[shelf], 0).apply(song);

		final rack = song.rack[Part.Dac.index()];
		final bank = song.banks[song.bankOf(rack)];

		final hits:Array<Int> = [];
		for (pitch in 0...128) if (song.drumAt(pitch) >= 0) hits.push(pitch);

		final named = where + "/kitted.mdsyn";
		Project.save(song, named);

		final back = Project.open(named);
		final again:Array<Int> = [];

		for (pitch in 0...128) if (back.drumAt(pitch) >= 0) again.push(pitch);

		says("a kit is written whole", again.join(",") == hits.join(",") && hits.length == 12,
			hits.length + " keys sound out of a bank of " + bank.instruments.length
			+ " the piece never names one by one, and " + again.length + " after the file is read back");
	}

	/**
		A file written before a piece carried only what it plays still opens as it was, and the
		next save leaves out what nothing in it plays. The example project that ships is one.
	**/
	static function older(where:String):Void {
		final from = Gate.root + "/assets/example-projects/console-tricks.mdsyn";

		if (!sys.FileSystem.exists(from)) {
			says("an older file sheds what it does not play", false, "no example project to open");
			return;
		}

		final song = Project.open(from);
		final playing = Needed.of(song).instruments.length;

		final before = new Stream(262144);
		new Sequencer(song).emit(before, 0, SPAN);

		final named = where + "/older.mdsyn";
		Project.save(song, named);

		final back = Project.open(named);
		final after = new Stream(262144);
		new Sequencer(back).emit(after, 0, SPAN);

		says("an older file sheds what it does not play", back.instruments.length == playing
			&& playing < song.instruments.length && alike(before, after) == -2,
			song.instruments.length + " presets in the file as it ships, " + back.instruments.length
			+ " once saved again, and " + before.count + " register writes the same either way");
	}

	/**
		A converter preset read back from a file has the identity of what it plays.

		A file's recordings arrive after its document, so an identity taken while the document is
		read hashes a buffer of the right length with nothing in it. Every hit then reads as a
		different preset from the same hit anywhere else, and a library that ships it never
		recognises it in a piece.
	**/
	static function heard(where:String):Void {
		final song = StreamCheck.written();
		var at = -1;

		for (index in 0...song.instruments.length) if (song.instruments[index].sample >= 0) at = index;

		final made = song.instruments[at];
		final meant = made.identifies(song.sampleAt(made.sample));

		for (form in ["heard.mdsyn", "heard folder"]) {
			final named = where + "/" + form;
			Project.save(song, named);

			final back = Project.open(named);
			var held:Null<Instrument> = null;

			for (one in back.instruments) if (one.sample >= 0 && one.name == made.name) held = one;

			final got = held == null ? "" : held.id;
			final again = held == null ? "" : held.copy().identifies(back.sampleAt(held.sample));

			says("a hit read back is what it plays" + (form == "heard.mdsyn" ? "" : ", from a folder"),
				got == meant && again == meant,
				"written as " + meant + ", read back as " + (got == "" ? "nothing" : got));
		}
	}

	/**
		@return A library standing in for a filled presets folder: two banks of presets nothing in
			the fixture plays, one of them a kit.
	**/
	static function stocked():Library {
		final out = new Library();

		for (index in 0...40) {
			final one = new Instrument("Shipped " + index, Part.Fm1);

			one.patch.feedback = index & 7;
			one.identifies(null);

			out.adds("Shipped", one, null, true);
		}

		for (index in 0...12) {
			final one = new Instrument("Hit " + index, Part.Dac);
			final sample = new mdd.song.Sample("hit " + index, 8000, 24 + index);
			final bytes = new haxe.ds.Vector<Int>(64);

			for (at in 0...bytes.length) bytes[at] = (at * 7 + index) & 0xFF;

			sample.hold(bytes);
			one.identifies(sample);

			out.adds("Spare Kit", one, sample, true);
		}

		return out;
	}

	/**
		@param song A piece read back from a file.
		@return How many of its recordings nothing plays.
	**/
	static function orphans(song:Song):Int {
		var many = 0;

		for (index in 0...song.samples.length) {
			var played = false;

			for (held in song.instruments) if (held.sample == index) played = true;
			if (!played) many++;
		}

		return many;
	}

	static function alike(one:Stream, two:Stream):Int {
		if (one.count != two.count) return -1;

		for (index in 0...one.count) {
			if (one.tickAt(index) != two.tickAt(index)) return index;
			if (one.kindAt(index) != two.kindAt(index)) return index;
			if (one.portAt(index) != two.portAt(index)) return index;
			if (one.valueAt(index) != two.valueAt(index)) return index;
		}

		return -2;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 46) + said + (ok ? "" : "   FAILED"));
	}
}
