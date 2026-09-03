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

		says("a shape survives being written and read", right == Automation.SHAPES,
			right + " of " + Automation.SHAPES
			+ " points keep their shape, tension and step count through the project format");
	}
}
