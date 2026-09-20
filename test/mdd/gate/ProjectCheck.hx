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
	A file carries the piece, not the presets library that was open beside it.

	A piece open in the application holds every bank the browser shows, which on a machine with a
	filled presets folder is hundreds of presets the piece never plays. Writing them put a copy of
	the library into every file, made a piece of twenty presets report a thousand, and grew with
	the folder rather than with the music. What a file has to carry is what the piece plays, and
	the proof that the right thing was left out is that the register stream is the same afterwards.
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
		kept(where);
		older();

		mdd.host.Paths.clear(where);

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");
		Sys.println(failed == 0 ? "    passed" : "    failed");

		return failed == 0 ? 0 : 1;
	}

	/**
		A piece with the whole library beside it is written as the piece, and it sounds the same
		when it is read back.
	**/
	static function carried(where:String):Void {
		final song = StreamCheck.written();
		final library = stocked();

		final own = song.instruments.length;
		final added = library.into(song);

		final before = new Stream(262144);
		new Sequencer(song).emit(before, 0, SPAN);

		final named = where + "/carried.mdsyn";
		Project.save(song, named);

		final back = Project.open(named);

		says("a file carries the piece rather than the library",
			back.instruments.length < own + added && back.instruments.length >= own,
			song.instruments.length + " presets open, " + added + " of them the library's, "
			+ back.instruments.length + " written");

		var reaches = 0;

		for (held in back.instruments) {
			if (held.sample < 0) continue;
			if (back.sampleAt(held.sample) != null) reaches++;
		}

		says("and no recording it does not play", back.samples.length < song.samples.length
			&& reaches > 0 && orphans(back) == 0,
			back.samples.length + " recordings written of " + song.samples.length
			+ ", every one of them played by " + reaches + " presets");

		final after = new Stream(262144);
		new Sequencer(back).emit(after, 0, SPAN);

		says("and it sounds the same", before.count > 0 && alike(before, after) == -2,
			before.count + " register writes over " + SPAN + " samples, and the file reads back "
			+ after.count + ", " + (alike(before, after) == -2 ? "every one the same"
			: "differing at " + alike(before, after)));

		final held = library.into(back);

		says("and the library puts back what was left out", held == added,
			held + " presets came back against " + added + " left out");
	}

	/**
		The kit behind a converter preset is written whole, because a hit is picked by note out of
		a bank rather than named by the note.
	**/
	static function kitted(where:String):Void {
		final song = StreamCheck.written();
		final library = stocked();

		library.into(song);

		final spare = song.banked("Spare Kit");
		song.rack[Part.Dac.index()] = spare.instruments[0];

		final rack = song.rack[Part.Dac.index()];
		final bank = song.banks[song.bankOf(rack)];

		final hits:Array<Int> = [];
		for (pitch in 0...128) if (song.drumAt(pitch) >= 0) hits.push(pitch);

		final named = where + "/kitted.mdsyn";
		Project.save(song, named);

		final back = Project.open(named);
		final again:Array<Int> = [];

		for (pitch in 0...128) if (back.drumAt(pitch) >= 0) again.push(pitch);

		says("a kit is written whole", again.join(",") == hits.join(",") && hits.length > 1,
			hits.length + " keys sound out of a bank of " + bank.instruments.length
			+ " the piece never names, and " + again.length + " after the file is read back");
	}

	/**
		A bank the reader asked to keep is written whole, even where nothing plays it.
	**/
	static function kept(where:String):Void {
		final song = StreamCheck.written();
		final library = stocked();

		library.into(song);

		final wanted = song.banked("Shipped");
		final many = wanted.instruments.length;

		says("a library bank is the library's", !wanted.kept && many > 0,
			many + " presets in a bank the piece did not ask for");

		final loose = Project.open(keeping(where, song, "loose"));

		wanted.kept = true;

		final whole = Project.open(keeping(where, song, "whole"));

		says("and keeping it writes it whole", whole.instruments.length
			== loose.instruments.length + many,
			loose.instruments.length + " presets written while it was the library's, "
			+ whole.instruments.length + " once it was kept");
	}

	/**
		A file written before a piece carried what it plays says every bank is the piece's own,
		because the library said so, so it is read as saying none of them is.
	**/
	static function older():Void {
		final song = StreamCheck.written();
		stocked().into(song);

		final said = Project.text(song);
		final older = StringTools.replace(said, "\"version\": " + Project.VERSION,
			"\"version\": " + Project.WHOLE_LIBRARY);

		says("a file says which version wrote it", older != said,
			"written as version " + Project.VERSION);

		final back = Project.read(older);
		var owned = 0;

		for (bank in back.banks) if (bank.kept) owned++;

		says("and one written before this is read as the library's", owned == 0,
			back.banks.length + " banks read back, " + owned + " of them the piece's own, so the"
			+ " next save leaves the library out");
	}

	/**
		@param where The folder to write into.
		@param song The piece.
		@param called What to call the file.
		@return Where it was written.
	**/
	static function keeping(where:String, song:Song, called:String):String {
		final named = where + "/" + called + ".mdsyn";
		Project.save(song, named);

		return named;
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
