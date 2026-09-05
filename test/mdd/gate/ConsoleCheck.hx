package mdd.gate;

import haxe.ds.Vector;
import mdd.format.Wav;
import mdd.play.Mixdown;
import mdd.play.Mixing;
import mdd.play.Render;

@:unreflective
class ConsoleCheck {
	static final BANDS:Array<Float> = [125, 200, 315, 500, 800, 1250, 2000, 2840, 4000, 5000,
		6300, 8000, 10000, 12500, 16000];

	static final PER_BAND = 3;
	static inline final REFERENCE = 500.0;

	static var ran = 0;
	static var failed = 0;

	public static function run(args:Array<String>):Int {
		var want = "";
		var into = "";
		var console = Render.CHIP;
		var rate = 44100;
		var stage = Render.MODEL_ONE;

		var at = 0;

		while (at < args.length) {
			final one = args[at];
			final held = at + 1 < args.length ? args[at + 1] : "";

			switch (one) {
				case "--vgm": want = held; at++;
				case "--out": into = held; at++;
				case "--console": console = whole(held, console); at++;
				case "--rate": rate = whole(held, rate); at++;
				case "--stage": stage = whole(held, stage); at++;
				default:
			}

			at++;
		}

		if (want != "" && into != "") return written(want, into, console, rate);

		ran = 0;
		failed = 0;

		Sys.println("  console");
		measured(stage);

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");
		Sys.println(failed == 0 ? "    passed" : "    failed");

		return failed == 0 ? 0 : 1;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 38) + said + (ok ? "" : "   FAILED"));
	}

	static function measured(stage:Int):Void {
		final where = Gate.root + "/vendor/console";

		if (!sys.FileSystem.isDirectory(where)) {
			says("a render matches the console it came from", true,
				"no captures in vendor/console, so there is nothing to measure against");

			return;
		}

		final tracks = ["Emerald Hill"];

		for (track in tracks) {
			final capture = captured(where, track);
			final name = Fixtures.found(track);

			if (capture == "" || name == "") continue;

			final held = Wav.read(sys.io.File.getBytes(capture));
			final theirs = banded(held.mono(), held.rate);

			final source = new mdd.play.Stream(1 << 22);
			final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name), source);
			final song = mdd.format.Transcription.of(source, vgm.rate, name).song;

			final mixing = new Mixing();

			mixing.rate = held.rate;
			mixing.padStart = 0;
			mixing.padEnd = 0;
			mixing.normalise = false;
			mixing.stereo = false;
			mixing.console = stage;

			final made = Mixdown.of(song, mixing);
			final mine = banded(floated(made.samples, made.frames), held.rate);

			var total = 0.0;
			var worst = 0.0;
			var worstAt = 0.0;

			for (index in 0...BANDS.length) {
				final gap = theirs[index] - mine[index];
				final away = gap < 0 ? -gap : gap;

				total += away * away;

				if (away > worst) {
					worst = away;
					worstAt = BANDS[index];
				}
			}

			final rms = Math.sqrt(total / BANDS.length);

			says("a render matches the console it came from", rms < 0.8 && worst < 1.8,
				track + " sits " + round(rms) + " dB from the capture across "
				+ BANDS.length + " bands, worst " + round(worst) + " dB at "
				+ Math.round(worstAt) + " Hz");
		}
	}

	static function captured(where:String, track:String):String {
		for (name in sys.FileSystem.readDirectory(where)) {
			if (name.toLowerCase().indexOf(".wav") < 0) continue;
			if (name.indexOf(track) < 0) continue;

			return where + "/" + name;
		}

		return "";
	}

	static function floated(from:Vector<cpp.Float32>, frames:Int):Vector<Float> {
		final out = new Vector<Float>(frames);
		for (index in 0...frames) out[index] = from[index];

		return out;
	}

	static inline final WINDOW = 4096;

	static function banded(held:Vector<Float>, rate:Int):Array<Float> {
		final many = BANDS.length * PER_BAND;

		final turns = new Vector<Float>(many);
		final power = new Vector<Float>(many);

		for (index in 0...BANDS.length) {
			for (step in 0...PER_BAND) {
				final spread = Math.pow(1.12, (step - (PER_BAND - 1) * 0.5) / (PER_BAND * 0.5));
				final hertz = BANDS[index] * spread;

				turns[index * PER_BAND + step] = 2 * Math.cos(2 * Math.PI * hertz / rate);
				power[index * PER_BAND + step] = 0;
			}
		}

		final shape = new Vector<Float>(WINDOW);
		for (at in 0...WINDOW) shape[at] = 0.5 - 0.5 * Math.cos(2 * Math.PI * at / (WINDOW - 1));

		final older = new Vector<Float>(many);
		final oldest = new Vector<Float>(many);

		var from = 0;
		var blocks = 0;

		while (from + WINDOW <= held.length) {
			for (index in 0...many) {
				older[index] = 0;
				oldest[index] = 0;
			}

			for (at in 0...WINDOW) {
				final sample = held[from + at] * shape[at];

				for (index in 0...many) {
					final now = sample + turns[index] * older[index] - oldest[index];

					oldest[index] = older[index];
					older[index] = now;
				}
			}

			for (index in 0...many) {
				final one = older[index];
				final two = oldest[index];

				power[index] += one * one + two * two - turns[index] * one * two;
			}

			from += WINDOW;
			blocks++;
		}

		final out:Array<Float> = [];

		for (index in 0...BANDS.length) {
			var total = 0.0;
			for (step in 0...PER_BAND) total += power[index * PER_BAND + step];

			if (blocks > 0) total /= blocks;

			out.push(10 * Math.log(total <= 0 ? 1e-30 : total) / Math.log(10));
		}

		var base = 0.0;
		for (index in 0...BANDS.length) if (BANDS[index] == REFERENCE) base = out[index];

		for (index in 0...out.length) out[index] -= base;

		return out;
	}

	static function written(want:String, into:String, console:Int, rate:Int):Int {
		final name = Fixtures.found(want);

		if (name == "") {
			Sys.println("  console       no fixture matching " + want);
			return 1;
		}

		final source = new mdd.play.Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name), source);
		final song = mdd.format.Transcription.of(source, vgm.rate, name).song;

		final mixing = new Mixing();

		mixing.rate = rate;
		mixing.padStart = 0;
		mixing.padEnd = 0;
		mixing.normalise = false;
		mixing.stereo = true;
		mixing.console = console;

		final made = Mixdown.of(song, mixing);

		sys.io.File.saveBytes(into,
			Wav.write(made.samples, made.frames, made.channels, rate, 16, false));

		Sys.println("  console       " + Fixtures.titled(name) + " at stage " + console
			+ ", " + made.frames + " frames, to " + into);

		return 0;
	}

	static function round(value:Float):Float {
		return Math.round(value * 100) / 100;
	}

	static function whole(said:String, fallback:Int):Int {
		final held = Std.parseInt(said);
		return held == null ? fallback : held;
	}
}
