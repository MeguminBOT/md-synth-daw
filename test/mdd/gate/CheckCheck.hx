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
		ranges();
		registers();
		speed();

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;
		Sys.println("    " + StringTools.rpad(name, " ", 34) + said + (ok ? "" : "   FAILED"));
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
			if (StringTools.startsWith(found.saying, "a key on")) keys++;
			else if (StringTools.startsWith(found.saying, "a write reached a register")) wrote++;
		}

		says("a register that is not there", wrote > 0,
			wrote + " writes name a register the Master System does not have");

		says("a key on that is not there", keys > 0,
			keys + " key ons name a channel it does not have");
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
