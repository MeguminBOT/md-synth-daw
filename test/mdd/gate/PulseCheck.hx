package mdd.gate;

import mdd.format.Pulse;
import mdd.format.Vgm;
import mdd.play.Stream;

@:unreflective
class PulseCheck {
	static inline final DIVISION = 4;
	static inline final TOLERANCE = 0.12;

	static var ran = 0;
	static var failed = 0;

	public static function run(args:Array<String>):Int {
		ran = 0;
		failed = 0;

		Sys.println("  pulse");

		transformed();

		final loud = args.indexOf("--each") >= 0;
		final deep = args.indexOf("--dsp") >= 0;

		if (deep) return weighed(args);
		final files = Fixtures.corpus();

		if (files.length == 0) {
			says("a stream says how fast it is", true, "no vgm corpus to read");
			return 0;
		}

		var read = 0;
		var better = 0;
		var worse = 0;
		var weak = 0;
		var onGrid = 0.0;
		var wasGrid = 0.0;

		var worstName = "";
		var worst = 2.0;

		for (name in files) {
			if (name.toLowerCase().indexOf(".vgm") < 0) continue;

			final stream = new Stream(1 << 22);
			final vgm = Vgm.read(sys.io.File.getBytes(name), stream);

			final onsets = Pulse.struck(stream, vgm.rate);
			if (onsets.length < 32) continue;

			final fallback = vgm.rate == 50 ? 125.0 : 150.0;
			final beats = Pulse.from(onsets, fallback);

			final now = Pulse.fits(onsets, beats);
			final was = Pulse.fits(onsets, fallback);

			read++;
			onGrid += now;
			wasGrid += was;

			if (now > was) better++;
			if (now < was) worse++;
			if (now < 0.5) weak++;

			if (now < worst) {
				worst = now;
				worstName = Fixtures.titled(name);
			}

			if (loud) {
				Sys.println("    " + StringTools.rpad(Fixtures.titled(name), " ", 34)
					+ StringTools.lpad("" + round(beats, 2), " ", 7) + " bpm, "
					+ Math.round(now * 100) + " per cent on the grid against "
					+ Math.round(was * 100) + " at " + Math.round(fallback));
			}
		}

		if (read == 0) {
			says("a stream says how fast it is", true, "nothing in the corpus carries onsets");
			return 0;
		}

		final mine = onGrid / read;
		final theirs = wasGrid / read;

		says("a detected tempo puts the notes on the grid", mine > 0.8 && mine > theirs,
			Math.round(mine * 1000) / 10 + " per cent of onsets land on a sixteenth across "
			+ read + " files, against " + Math.round(theirs * 1000) / 10
			+ " at the frame rate, and " + better + " of them improved");

		says("and keeping the frame rate when it fits better", worse == 0,
			worse + " of " + read + " files came out worse than the rate they were logged at");

		says("and what is left is free of a pulse", weak * 5 <= read,
			weak + " of " + read + " files sit under half, the weakest being " + worstName
			+ " at " + Math.round(worst * 100) + " per cent, which is what a piece with no"
			+ " steady beat looks like");

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");
		Sys.println(failed == 0 ? "    passed" : "    failed");

		return failed == 0 ? 0 : 1;
	}

	static function transformed():Void {
		final size = 1024;
		final fourier = new Fourier(size);

		final bin = 37;
		var energy = 0.0;

		fourier.clear();

		for (index in 0...size) {
			final value = Math.cos(2 * Math.PI * bin * index / size);

			fourier.real[index] = value;
			energy += value * value;
		}

		fourier.forward();

		final held = new haxe.ds.Vector<Float>(size >> 1);
		fourier.magnitudes(held);

		var loudest = 0.0;
		var where = -1;
		var others = 0.0;

		for (index in 0...size >> 1) {
			if (held[index] > loudest) {
				loudest = held[index];
				where = index;
			}
		}

		for (index in 0...size >> 1) if (index != where) others += held[index];

		var total = 0.0;
		for (index in 0...size) {
			total += fourier.real[index] * fourier.real[index]
				+ fourier.imaginary[index] * fourier.imaginary[index];
		}

		final kept = total / size;

		says("a transform puts a tone in its own bin",
			where == bin && Math.abs(loudest - size * 0.5) < 0.001 && others < 0.001
			&& Math.abs(kept - energy) < 0.001,
			"a cosine at bin " + bin + " reads " + Math.round(loudest) + " there and "
			+ round(others, 6) + " across the rest, and the energy comes back as "
			+ Math.round(kept) + " against " + Math.round(energy));
	}

	static function weighed(args:Array<String>):Int {
		final files = Fixtures.corpus();

		var read = 0;
		var flat = 0.0;
		var deep = 0.0;
		var rate = 0.0;
		var better = 0;

		final began = haxe.Timer.stamp();

		for (name in files) {
			if (name.toLowerCase().indexOf(".vgm") < 0) continue;
			if (read >= 24) break;
			final only = args.indexOf("--weak") >= 0;

			final stream = new Stream(1 << 22);
			final vgm = Vgm.read(sys.io.File.getBytes(name), stream);

			final onsets = Pulse.struck(stream, vgm.rate);
			if (onsets.length < 32) continue;

			final fallback = vgm.rate == 50 ? 125.0 : 150.0;

			final one = Pulse.from(onsets, fallback);
			if (only && Pulse.fits(onsets, one) >= 0.5) continue;
			final two = Sounded.paced(Sounded.heard(stream), fallback);

			final oneFit = Pulse.fits(onsets, one);
			final twoFit = Pulse.fits(onsets, two);

			read++;
			flat += oneFit;
			deep += twoFit;
			rate += Pulse.fits(onsets, fallback);

			if (twoFit > oneFit) better++;

			Sys.println("    " + StringTools.rpad(Fixtures.titled(name), " ", 32)
				+ "onsets " + round(one, 2) + " at " + Math.round(oneFit * 100)
				+ " per cent, sound " + round(two, 2) + " at " + Math.round(twoFit * 100));
		}

		if (read == 0) return 0;

		Sys.println("    " + read + " files in " + Math.round(haxe.Timer.stamp() - began)
			+ " s: onsets " + Math.round(flat / read * 1000) / 10 + " per cent, sound "
			+ Math.round(deep / read * 1000) / 10 + ", the rate they were logged at "
			+ Math.round(rate / read * 1000) / 10 + ", sound ahead on " + better);

		return 0;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 44) + said + (ok ? "" : "   FAILED"));
	}

	static function round(value:Float, places:Int):Float {
		final scale = Math.pow(10, places);
		return Math.round(value * scale) / scale;
	}
}
