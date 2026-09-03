package mdd.gate;

import mdd.song.Automation;
import mdd.song.Part;
import mdd.song.Pattern;
import mdd.song.Point;
import mdd.song.Song;

@:unreflective
class AutomationCheck {
	static inline final SPAN = 384;
	static inline final LOW = 10;
	static inline final HIGH = 90;

	static final NAMES:Array<String> = ["hold", "linear", "curve", "smooth", "stairs",
		"smooth stairs", "pulse", "wave", "half sine"];

	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  automation");

		ends();
		middles();
		bent();
		repeated();
		played();
		clipped();
		named();
		kept();

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

	static function line(shape:Int, tension:Int = 0, steps:Int = 0):Automation {
		final held = new Automation(Automation.LEVEL, 0);
		final from = new Point(0, LOW);

		from.shape = shape;
		from.tension = tension;
		from.steps = steps;

		held.add(from);
		held.add(new Point(SPAN, HIGH));

		return held;
	}

	static function ends():Void {
		final said = new StringBuf();
		var right = 0;

		for (shape in 0...Automation.SHAPES) {
			final held = line(shape);
			final head = held.valueAt(0);
			final tail = held.valueAt(SPAN);

			if (head == LOW && tail == HIGH) right++;
			else said.add(NAMES[shape] + " " + head + ".." + tail + "  ");
		}

		says("every shape starts and ends where it is put", right == Automation.SHAPES,
			right + " of " + Automation.SHAPES + " shapes hold " + LOW + " at the first point"
			+ " and " + HIGH + " at the second"
			+ (said.toString() == "" ? "" : ", against " + said.toString()));
	}

	static function middles():Void {
		final half = Std.int(SPAN / 2);

		final held = line(Automation.HOLD).valueAt(half);
		final straight = line(Automation.LINEAR).valueAt(half);
		final smooth = line(Automation.SMOOTH).valueAt(half);
		final sine = line(Automation.HALF_SINE).valueAt(half);

		says("hold keeps its value until the next point", held == LOW,
			"a hold segment reads " + held + " half way from " + LOW + " to " + HIGH);

		says("linear is half way at half way", straight == 50,
			"a linear segment reads " + straight + " half way from " + LOW + " to " + HIGH);

		says("smooth and half sine are half way too", smooth == 50 && sine == 50,
			"smooth reads " + smooth + " and half sine " + sine
			+ ", and they differ elsewhere: at a quarter they are "
			+ line(Automation.SMOOTH).valueAt(Std.int(SPAN / 4)) + " and "
			+ line(Automation.HALF_SINE).valueAt(Std.int(SPAN / 4)));
	}

	static function bent():Void {
		final at = Std.int(SPAN / 2);

		final none = line(Automation.CURVE, 0).valueAt(at);
		final slow = line(Automation.CURVE, 100).valueAt(at);
		final fast = line(Automation.CURVE, -100).valueAt(at);

		says("tension bends a curve both ways", slow < none && fast > none,
			"half way along, tension -100 reads " + fast + ", none reads " + none
			+ " and tension 100 reads " + slow);

		var rises = true;
		var last = -1;

		for (step in 0...33) {
			final held = line(Automation.CURVE, 60).valueAt(Std.int(SPAN * step / 32));
			if (held < last) rises = false;

			last = held;
		}

		says("and a bent curve still only rises", rises,
			"33 samples of a curve at tension 60 never go back on themselves");
	}

	static function repeated():Void {
		final stairs = line(Automation.STAIRS, 0, 4);
		final levels:Array<Int> = [];

		for (step in 0...64) {
			final held = stairs.valueAt(Std.int(SPAN * step / 64));
			if (levels.indexOf(held) < 0) levels.push(held);
		}

		says("stairs takes as many levels as it is asked for", levels.length == 4,
			"a four step stairs takes " + levels.length + " levels across the segment: "
			+ levels.join(", "));

		final pulse = line(Automation.PULSE, 0, 3);
		var edges = 0;
		var was = pulse.valueAt(0);

		for (step in 1...256) {
			final held = pulse.valueAt(Std.int(SPAN * step / 256));
			if (held != was) edges++;

			was = held;
		}

		says("a pulse alternates as often as it is asked to", edges == 5,
			"a three cycle pulse changes " + edges + " times inside the segment");

		final wave = line(Automation.WAVE, 0, 2);
		final middle = Std.int((LOW + HIGH) / 2);

		var risen = 0;
		var under = wave.valueAt(0) < middle;

		for (step in 1...256) {
			final over = wave.valueAt(Std.int(SPAN * step / 256)) >= middle;

			if (over && under) risen++;
			under = !over;
		}

		says("and a wave rises once a cycle", risen == 2,
			"a two cycle wave passes the halfway value going up " + risen + " times");
	}

	static function sung(shape:Int, steps:Int):Array<Int> {
		final song = new Song("ramp", 96, 120);
		final pattern = song.add(new Pattern("pattern 1", SPAN * 2));
		final lane = pattern.lane(Part.Psg1);

		lane.add(new mdd.song.Note(0, SPAN * 2, 60, 127));

		final held = new Automation(Automation.LEVEL, 0);
		final from = new Point(0, 0);

		from.shape = shape;
		from.steps = steps;

		held.add(from);
		held.add(new Point(SPAN, 12));
		lane.automation.push(held);

		final track = song.track(new mdd.song.Track("one"));
		track.add(new mdd.song.Clip(0, 0, pattern.length));

		final stream = new mdd.play.Stream(1 << 16);
		final span = song.tempo.samplesAt(pattern.length);

		new mdd.play.Sequencer(song).spanned(stream, 0, span);

		final out:Array<Int> = [];
		var latched = 0;

		for (index in 0...stream.count) {
			if (stream.kindAt(index) != mdd.play.Stream.PSG) continue;

			final value = stream.valueAt(index);
			if ((value & 0x80) == 0) continue;

			latched = (value >> 4) & 7;
			if ((latched & 1) == 0) continue;

			out.push(value & 0x0F);
		}

		return out;
	}

	static function played():Void {
		final held = sung(Automation.HOLD, 0);
		final straight = sung(Automation.LINEAR, 0);
		final stairs = sung(Automation.STAIRS, 4);

		says("a hold segment writes once and no more", held.length <= 2,
			"a held level writes the attenuation " + held.length + " times across "
			+ SPAN + " ticks");

		var rises = true;
		for (index in 1...straight.length) if (straight[index] < straight[index - 1]) rises = false;

		says("a linear segment ramps to its far value", straight.length >= 12
			&& rises && straight[straight.length - 1] == 12,
			"a linear level writes " + straight.length
			+ " attenuations, each quieter than the last, ending on "
			+ straight[straight.length - 1] + ", which is the offset the far point carries");

		says("and never writes the same value twice running", rises && every(straight),
			"no two of the " + straight.length + " writes carry the same value in a row");

		says("a stairs segment writes once a step", stairs.length >= 4
			&& stairs.length < straight.length,
			"a four step stairs writes " + stairs.length + " attenuations against "
			+ straight.length + " for the same span drawn linear");
	}

	static function every(held:Array<Int>):Bool {
		for (index in 1...held.length) if (held[index] == held[index - 1]) return false;
		return true;
	}

	static function drove(shape:Int):Array<Int> {
		final song = new Song("clip", 96, 120);
		final pattern = song.add(new Pattern("pattern 1", SPAN * 2));

		pattern.lane(Part.Psg1).add(new mdd.song.Note(0, SPAN * 2, 60, 127));

		final notes = song.track(new mdd.song.Track("notes"));
		notes.add(new mdd.song.Clip(0, 0, pattern.length));

		final driving = song.track(new mdd.song.Track("driving"));
		final clip = mdd.song.Clip.drives(Part.Psg1, Automation.LEVEL, 0, 0, SPAN);
		final line = clip.line;

		if (line != null) {
			final from = new Point(0, 0);
			from.shape = shape;

			line.add(from);
			line.add(new Point(SPAN, 12));
		}

		driving.add(clip);

		final stream = new mdd.play.Stream(1 << 16);
		new mdd.play.Sequencer(song).spanned(stream, 0,
			song.tempo.samplesAt(pattern.length));

		final out:Array<Int> = [];
		var latched = 0;

		for (index in 0...stream.count) {
			if (stream.kindAt(index) != mdd.play.Stream.PSG) continue;

			final value = stream.valueAt(index);
			if ((value & 0x80) == 0) continue;

			latched = (value >> 4) & 7;
			if ((latched & 1) == 0) continue;

			out.push(value & 0x0F);
		}

		return out;
	}

	static function clipped():Void {
		final held = drove(Automation.HOLD);
		final straight = drove(Automation.LINEAR);

		says("a clip on the playlist drives a part it does not hold",
			held.length >= 2 && held[held.length - 1] == 12,
			"an automation clip over a square on another track writes " + held.length
			+ " attenuations, ending on " + held[held.length - 1]
			+ ", which is the offset its far point carries");

		var rises = true;
		for (index in 1...straight.length) {
			if (straight[index] < straight[index - 1]) rises = false;
		}

		says("and a shape in it ramps the same way a lane does",
			straight.length > held.length && rises,
			"the same clip drawn linear writes " + straight.length
			+ " attenuations against " + held.length + " held, each quieter than the last");
	}

	static function named():Void {
		var many = 0;
		var packed = 0;

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final held = mdd.view.Parameter.of(part);

			many += held.length;

			for (one in held) {
				if (one.smooth) continue;
				packed++;
			}
		}

		final fm = mdd.view.Parameter.of(Part.Fm1).length;
		final square = mdd.view.Parameter.of(Part.Psg1).length;
		final noise = mdd.view.Parameter.of(Part.Noise).length;
		final sampled = mdd.view.Parameter.of(Part.Dac).length;

		says("every part says what can be automated on it",
			fm == 10 && square == 2 && noise == 2 && sampled == 1 && packed == 44,
			many + " parameters over the eleven parts: " + fm + " on an fm channel, "
			+ square + " on a square, " + noise + " on the noise and " + sampled
			+ " on the converter. " + packed + " of them are registers carrying more than"
			+ " one setting, where a ramp would run one field into another, so they step");

		final where = Gate.root + "/vendor/vgm";
		if (!sys.FileSystem.isDirectory(where)) return;

		var name = "";
		for (held in sys.FileSystem.readDirectory(where)) {
			if (held.indexOf("Green Hill") >= 0) name = held;
		}

		if (name == "") return;

		final stream = new mdd.play.Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(where + "/" + name), stream);
		final song = mdd.format.Transcription.of(stream, vgm.rate, name).song;

		var lines = 0;
		var known = 0;
		final missing = new StringBuf();

		for (pattern in song.patterns) {
			for (index in 0...Part.COUNT) {
				final part:Part = index;

				for (line in pattern.lane(part).automation) {
					lines++;

					if (mdd.view.Parameter.found(part, line.target, line.slot) != null) {
						known++;
						continue;
					}

					missing.add(part.name() + " target " + line.target + "  ");
				}
			}
		}

		says("and covers everything an import writes", lines > 0 && known == lines,
			known + " of " + lines + " automation lines an imported file makes have a"
			+ " parameter that names them"
			+ (missing.toString() == "" ? "" : ", missing " + missing.toString()));
	}

	static function kept():Void {
		final song = new Song("shapes", 96, 120);
		final pattern = song.add(new Pattern("pattern 1", SPAN));
		final lane = pattern.lane(Part.Fm1);

		for (shape in 0...Automation.SHAPES) {
			final held = new Automation(Automation.LEVEL, shape);
			final from = new Point(0, LOW + shape);

			from.shape = shape;
			from.tension = shape * 10 - 40;
			from.steps = shape + 1;

			held.add(from);
			held.add(new Point(SPAN, HIGH));
			lane.automation.push(held);
		}

		final back = mdd.format.Project.read(mdd.format.Project.text(song));

		if (back == null) {
			says("a shape survives being written and read", false, "the project did not read");
			return;
		}

		final again = back.patternAt(0);
		final lines = again == null ? null : again.lane(Part.Fm1).automation;

		var right = 0;

		if (lines != null && lines.length == Automation.SHAPES) {
			for (shape in 0...Automation.SHAPES) {
				final one = lane.automation[shape].points[0];
				final two = lines[shape].points[0];

				if (one.shape != two.shape || one.tension != two.tension) continue;
				if (one.steps != two.steps || one.value != two.value) continue;

				right++;
			}
		}

		final driving = song.track(new mdd.song.Track("driving"));
		final clip = mdd.song.Clip.drives(Part.Psg1, Automation.TUNE, 0, 96, SPAN);
		final held = clip.line;

		if (held != null) {
			final from = new Point(0, -40);
			from.shape = Automation.WAVE;
			from.steps = 5;

			held.add(from);
			held.add(new Point(SPAN, 40));
		}

		driving.add(clip);

		final twice = mdd.format.Project.read(mdd.format.Project.text(song));
		var one:Null<mdd.song.Clip> = null;

		if (twice != null) {
			for (track in twice.tracks) {
				for (found in track.clips) if (found.drawn()) one = found;
			}
		}

		final line = one == null ? null : one.line;

		says("and so does a clip that drives one", line != null
			&& one.kind == mdd.song.Clip.AUTOMATION && one.part == Part.Psg1.index()
			&& one.at == 96 && line.target == Automation.TUNE
			&& line.points.length == 2 && line.points[0].shape == Automation.WAVE
			&& line.points[0].steps == 5 && line.points[0].value == -40,
			line == null ? "the clip did not come back"
			: "the clip comes back on " + (one.part:Part).name() + " at " + one.at
			+ " driving " + line.points.length + " points, the first a wave of "
			+ line.points[0].steps + " cycles holding " + line.points[0].value);

		says("a shape survives being written and read", right == Automation.SHAPES,
			right + " of " + Automation.SHAPES
			+ " points keep their shape, tension and step count through the project format");
	}
}
