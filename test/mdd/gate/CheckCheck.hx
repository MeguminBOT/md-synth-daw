package mdd.gate;

import mdd.check.Budget;
import mdd.check.Diagnostic;
import mdd.check.Profile;
import mdd.host.Sdl;
import mdd.play.Sequencer;
import mdd.play.Stream;
import mdd.song.Clip;
import mdd.song.Instrument;
import mdd.song.Note;
import mdd.song.Part;
import mdd.song.Pattern;
import mdd.song.Song;
import mdd.song.Tempo;
import mdd.song.Track;

@:unreflective
class CheckCheck {
	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  check");

		profiles();
		overlaps();
		converter();
		sampled();
		swapped();
		ranges();
		registers();
		speed();
		crowded();
		scales();

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	/**
		Swapping the converter's instrument changes what the converter plays.
	**/
	static function swapped():Void {
		final song = bare("swapping");

		final one = laid(song, "one", 60, 40);
		final two = laid(song, "two", 60, 200);

		song.banked("kit one").add(one);
		song.banked("kit two").add(two);

		song.bank(0).remove(one);
		song.bank(0).remove(two);

		song.rack[Part.Dac.index()] = one;
		song.patterns[0].lane(Part.Dac).add(new Note(0, 96, 60, 100));

		final before = poured(song);

		new mdd.song.edit.SetInstrument(Part.Dac, two).apply(song);

		final after = poured(song);

		says("swapping the converter's instrument changes what it plays",
			before != "" && after != "" && before != after,
			before == after ? "both instruments wrote the same bytes"
				: "the first wrote " + before + " and the second " + after);

		song.drums = true;

		final kitted = poured(song);

		new mdd.song.edit.SetInstrument(Part.Dac, one).apply(song);

		final back = poured(song);

		says("and swapping it changes what a kit reaches too",
			kitted != "" && back != "" && kitted != back,
			kitted == back
				? "both kits reached the same bytes, so the swap did nothing"
				: "the second kit wrote " + kitted + " and the first " + back
					+ ", from two kits with a hit on the same key");
	}

	/**
		Puts a sampled instrument in a song, its bytes a flat level so the two are told
		apart by what reaches the converter rather than by how much of it there is.

		@param song The song.
		@param name What to call it.
		@param root Which key it sits on.
		@param level The byte it holds.
		@return Its index.
	**/
	static function laid(song:Song, name:String, root:Int, level:Int):Int {
		final sample = new mdd.song.Sample(name, 8000, root);
		final bytes = new haxe.ds.Vector<Int>(64);

		for (at in 0...bytes.length) bytes[at] = level;
		sample.hold(bytes);

		song.sample(sample);

		final made = new Instrument(name, Part.Dac);
		made.sample = song.samples.length - 1;

		song.instrument(made);
		return song.instruments.length - 1;
	}

	/**
		@param song The song to sequence.
		@return The distinct bytes that reached the converter, or an empty string where
			none did.
	**/
	static function poured(song:Song):String {
		final span = song.tempo.samplesAt(song.ends());
		final stream = Stream.reserved(span);

		new Sequencer(song).spanned(stream, 0, span);

		final held:Array<String> = [];
		var want = false;

		for (index in 0...stream.count) {
			if (stream.kindAt(index) != Stream.YM) continue;

			if (stream.portAt(index) == 0) {
				want = stream.valueAt(index) == 0x2A;
				continue;
			}

			if (!want) continue;

			final said = "" + stream.valueAt(index);
			if (held.indexOf(said) < 0) held.push(said);
		}

		return held.join(" ");
	}

	/**
		A sample is counted where a note reaches it and nowhere else, so the banks that
		ship cost a new piece nothing at all.
	**/
	static function sampled():Void {
		final song = mdd.app.Session.empty(mdd.song.Library.embedded());
		final budget = new Budget(Profile.megaDrive());

		var held = 0;
		for (sample in song.samples) held += sample.length();

		budget.overSong(song);

		says("a new piece carries no samples at all", budget.sampleBytes == 0 && held > 0,
			budget.sampleBytes + " bytes counted against the " + held
				+ " the shipped banks put in the document");

		final rack = song.rack[Part.Dac.index()];
		final instrument = song.instrumentAt(rack);
		final sample = instrument == null ? null : song.sampleAt(instrument.sample);
		final want = sample == null ? 0 : sample.length();

		final pattern = song.patterns[0];

		pattern.lane(Part.Dac).add(new Note(0, 24, sample == null ? 60 : sample.root,
			100, rack));
		pattern.lane(Part.Dac).add(new Note(48, 24, sample == null ? 60 : sample.root,
			100, rack));

		budget.overSong(song);

		says("and one a note plays is counted once", budget.sampleBytes == want && want > 0,
			budget.sampleBytes + " bytes for two notes on the same " + want
				+ " byte sample");

		song.drums = true;
		pattern.lane(Part.Dac).notes[1].pitch = 99;

		budget.overSong(song);

		final kitted = budget.sampleBytes;

		pattern.lane(Part.Dac).notes[0].pitch = 99;
		budget.overSong(song);

		says("and a key the kit has nothing on costs nothing",
			kitted == want && budget.sampleBytes == 0,
			kitted + " bytes with one note on the kick's key and one on a key with"
				+ " nothing on it, " + budget.sampleBytes + " with both on empty keys");

		says("and the budget it starts at is a stated convention",
			Profile.megaDrive().sampleBytes == Profile.ROM && Profile.ROM == 262144
				&& Profile.masterSystem().sampleBytes == 0,
			Profile.ROM + " bytes, a quarter of a one megabyte cartridge, which an author"
				+ " sets against their own rather than a limit of the machine");
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;
		Sys.println("    " + StringTools.rpad(name, " ", 40) + said + (ok ? "" : "   FAILED"));
	}

	static function round(value:Float, places:Int):Float {
		final scale = Math.pow(10, places);
		return Math.round(value * scale) / scale;
	}

	static function bare(name:String):Song {
		final song = new Song(name, 96, 120);

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			song.instrument(new Instrument(part.name().toLowerCase(), part));
			song.rack[index] = index;
		}

		song.add(new Pattern("one", 384));

		final track = song.track(new Track("one"));
		track.add(new Clip(0, 0, 384));

		return song;
	}

	static function profiles():Void {
		final md = Profile.megaDrive();
		final sms = Profile.masterSystem();

		says("a profile names its parts", md.counted() == Part.COUNT && sms.counted() == 4,
			"the Mega Drive has " + md.counted() + " parts and the Master System " + sms.counted());

		says("registers belong to a part", md.holds(0, 0x2A) && !sms.holds(0, 0x2A)
			&& md.holds(1, 0x30) && !sms.holds(1, 0x30),
			"the converter and the second half are on one and not on the other");

		says("a key on names a channel", md.keyed(2) && !md.keyed(3) && !sms.keyed(0),
			"channel three of a half is not addressable, and neither is any FM on a Master System");
	}

	static function overlaps():Void {
		final song = bare("overlapping");
		final lane = song.patterns[0].lane(Part.Fm1);

		lane.add(new Note(0, 96, 60, 100));
		final second = lane.add(new Note(48, 96, 64, 100));
		lane.add(new Note(192, 48, 67, 100));

		final budget = new Budget(Profile.megaDrive());
		budget.overSong(song);

		says("one voice is one voice", budget.warnings() == 1 && budget.troubled(second),
			budget.warnings() + " warning, and the note it names is the one that starts inside "
			+ "the one before it");

		says("a warning links to its cause", budget.found[0].linked()
			&& budget.found[0].part == Part.Fm1,
			"it carries pattern " + budget.found[0].pattern + ", "
			+ budget.found[0].part.name() + " and the note itself");
	}

	static function converter():Void {
		final song = bare("the seventh voice");

		song.patterns[0].lane(Part.Fm6).add(new Note(0, 96, 60, 100));
		song.patterns[0].lane(Part.Dac).add(new Note(48, 48, 60, 100));

		final budget = new Budget(Profile.megaDrive());
		budget.overSong(song);

		var caught = false;
		for (found in budget.found) if (found.part == Part.Fm6) caught = true;

		says("the DAC holds FM6", caught && budget.faults == 1,
			"the sixth channel and the converter sounding together is " + budget.faults
			+ " fault, not a warning");

		final apart = bare("apart");
		apart.patterns[0].lane(Part.Fm6).add(new Note(0, 48, 60, 100));
		apart.patterns[0].lane(Part.Dac).add(new Note(96, 48, 60, 100));

		final quiet = new Budget(Profile.megaDrive());
		quiet.overSong(apart);

		says("and not when they take turns", quiet.faults == 0,
			"the same two notes with no overlap raise nothing");
	}

	static function ranges():Void {
		final song = bare("out of range");

		song.patterns[0].lane(Part.Psg1).add(new Note(0, 48, 30, 100));
		song.patterns[0].lane(Part.Psg1).add(new Note(96, 48, 60, 100));

		final budget = new Budget(Profile.megaDrive());
		budget.overSong(song);

		says("a square has a floor", budget.warnings() == 1,
			"note 30 is below what a ten bit period reaches and note 60 is not");

		final wrong = bare("wrong machine");
		wrong.patterns[0].lane(Part.Fm1).add(new Note(0, 48, 60, 100));

		final sms = new Budget(Profile.masterSystem());
		sms.overSong(wrong);

		says("a part that is not there", sms.faults == 1,
			"an FM note on a Master System is " + sms.faults + " fault");
	}

	static function registers():Void {
		final song = bare("a stream");
		song.patterns[0].lane(Part.Fm1).add(new Note(0, 48, 60, 100));
		song.patterns[0].lane(Part.Fm5).add(new Note(0, 48, 64, 100));
		song.patterns[0].lane(Part.Dac).add(new Note(96, 48, 60, 100));

		final stream = new Stream(65536);
		final sequencer = new Sequencer(song);
		sequencer.emit(stream, 0, song.tempo.samplesAt(384));

		final md = new Budget(Profile.megaDrive());
		md.overStream(stream);

		says("a stream that fits", md.faults == 0,
			stream.count + " writes and nothing the Mega Drive does not have");

		final sms = new Budget(Profile.masterSystem());
		sms.overStream(stream);

		var keys = 0;
		var wrote = 0;

		for (found in sms.found) {
			if (found.saying == mdd.app.Locale.WARN_KEY_ABSENT) keys++;
			else if (found.saying == mdd.app.Locale.WARN_REGISTER_ABSENT) wrote++;
		}

		says("a register that is not there", wrote > 0,
			wrote + " writes name a register the Master System does not have");

		says("a key on that is not there", keys > 0,
			keys + " key ons name a channel it does not have");
	}

	static function crowded():Void {
		final where = Gate.root + "/vendor/vgm";

		if (!sys.FileSystem.isDirectory(where)) {
			says("a frame holds only so many writes", true,
				"no corpus beside the build to measure against");
			return;
		}

		final counts = new haxe.ds.Vector<Int>(1024);
		for (index in 0...counts.length) counts[index] = 0;

		var most = 0;
		var mostIn = "";
		var settled = 0;
		var settledIn = "";
		var frames = 0;
		var files = 0;

		for (name in Fixtures.corpus()) {
			final stream = new mdd.play.Stream(1 << 22);
			mdd.format.Vgm.read(sys.io.File.getBytes(name), stream);
			files++;

			final frame = Std.int(mdd.song.Tempo.TICKS / 60);
			var at = 0;
			var index = 0;
			var address = -1;

			while (index < stream.count) {
				var many = 0;

				while (index < stream.count && stream.tickAt(index) < at + frame) {
					if (stream.kindAt(index) == mdd.play.Stream.PSG) many++;
					else if ((stream.portAt(index) & 1) == 0) {
						address = stream.valueAt(index);
					} else if (address != 0x2A) many++;

					index++;
				}

				frames++;
				if (many < counts.length) counts[many]++;

				if (many > most) {
					most = many;
					mostIn = name;
				}

				if (at >= frame * 60 && many > settled) {
					settled = many;
					settledIn = name;
				}

				at += frame;
			}
		}

		var ninety = 0;
		var seen = 0;

		for (many in 0...counts.length) {
			seen += counts[many];
			if (seen * 1000 >= frames * 999) {
				ninety = many;
				break;
			}
		}

		Sys.println("    " + files + " files, " + frames + " frames: the busiest writes "
			+ most + " registers, in " + mostIn + "; past the first second the busiest is "
			+ settled + ", in " + settledIn + "; 99.9 per cent of frames write "
			+ ninety + " or fewer");

		final busy = new mdd.play.Stream(1 << 14);
		final ceiling = mdd.check.Profile.megaDrive().perFrame;

		for (step in 0...ceiling * 2) {
			busy.ym(mdd.song.Tempo.TICKS, 0, 0x40, step & 0x7F);
		}

		final loud = new Budget(mdd.check.Profile.megaDrive());
		loud.overStream(busy);

		final quiet = new mdd.play.Stream(1 << 14);

		for (step in 0...Std.int(ceiling / 2)) {
			quiet.ym(mdd.song.Tempo.TICKS, 0, 0x40, step & 0x7F);
		}

		final calm = new Budget(mdd.check.Profile.megaDrive());
		calm.overStream(quiet);

		says("and says so when one does not", loud.warnings() == 1 && calm.warnings() == 0,
			(ceiling * 2) + " writes in one frame raises " + loud.warnings()
			+ " warning and " + Std.int(ceiling / 2) + " raises " + calm.warnings());

		says("a frame holds only so many writes",
			mdd.check.Profile.megaDrive().perFrame == settled,
			"the profile allows " + mdd.check.Profile.megaDrive().perFrame
			+ " register writes a frame, which is the busiest frame any of these games"
			+ " sustains once it is playing; the " + most + " in " + mostIn
			+ " is its opening burst, before anything sounds");
	}

	static function scales():Void {
		final scale = new mdd.song.Scale(0, mdd.song.Scale.CHROMATIC);

		var all = true;
		for (pitch in 48...72) if (!scale.holds(pitch)) all = false;

		says("chromatic holds everything", all && scale.degrees() == 12,
			"every one of twelve is in the chromatic scale, which is what makes it the default");

		scale.kind = mdd.song.Scale.MAJOR;
		scale.root = 0;

		final wanted = [0, 2, 4, 5, 7, 9, 11];
		var major = true;

		for (step in 0...12) {
			final inside = wanted.indexOf(step) >= 0;
			if (scale.holds(60 + step) != inside) major = false;
		}

		says("major is the major scale", major && scale.degrees() == 7 && scale.rooted(60)
			&& scale.rooted(72) && !scale.rooted(61),
			"C major lights " + scale.degrees() + " of twelve, and every C is the root");

		scale.root = 9;
		scale.kind = mdd.song.Scale.MINOR;

		var minor = true;
		for (step in [9, 11, 0, 2, 4, 5, 7]) if (!scale.holds(60 + step)) minor = false;
		for (step in [10, 1, 3, 6, 8]) if (scale.holds(60 + step)) minor = false;

		says("a natural minor moves with its root", minor && scale.rooted(69),
			"A minor lights the same pitches as C major, rooted on A instead");

		var named = true;
		for (kind in 0...mdd.song.Scale.KINDS) {
			if ((mdd.view.Scales.named(kind) : Int) < 0) named = false;
		}

		says("every scale has a name", named && mdd.song.Scale.rootOf(1) == "C#"
			&& mdd.song.Scale.rootOf(-1) == "B",
			mdd.song.Scale.KINDS + " scales, and a root that wraps below zero");
	}

	static function speed():Void {
		final song = StreamCheck.written();
		final pattern = song.patterns[0];

		var seed = 0x9E37;
		var placed = 0;

		for (index in 0...6) {
			final part:Part = index;
			var at = 0;

			while (at < 96 * 4 * 64) {
				seed = (seed * 1103515245 + 12345) & 0x3FFFFFFF;
				pattern.lane(part).add(new Note(at, 24, 48 + (seed >> 8) % 36, 100));
				placed++;
				at += 24;
			}
		}

		pattern.length = 96 * 4 * 64;

		final budget = new Budget(Profile.megaDrive());

		budget.overSong(song);
		final began = Sdl.ticks();
		budget.overSong(song);
		final spent = (Sdl.ticks() - began) * 1000;

		says("a whole song inside a frame", spent < 16.67,
			placed + " notes checked in " + round(spent, 3) + " ms, of 16.67 in a frame, "
			+ budget.warnings() + " warnings found");
	}
}
