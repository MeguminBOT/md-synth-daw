package mdd.play;

import haxe.ds.Vector;

@:unreflective
final class Velocity {
	public static inline final FULL = 127;
	static inline final SILENT = 127;
	static inline final PSG_OFF = 15;

	static inline final FM_DECIBELS = 0.75;
	static inline final PSG_DECIBELS = 2.0;

	static final FM:Vector<Int> = attenuations(FM_DECIBELS, SILENT);
	static final PSG:Vector<Int> = attenuations(PSG_DECIBELS, PSG_OFF);
	static final LOUDNESS:Vector<Int> = loudnesses();

	static function attenuations(decibels:Float, most:Int):Vector<Int> {
		final out = new Vector<Int>(FULL + 1);

		out[0] = most;

		for (velocity in 1...FULL + 1) {
			final down = -20 * Math.log(velocity / FULL) / Math.log(10);
			var steps = Math.round(down / decibels);

			if (steps < 0) steps = 0;
			if (steps > most) steps = most;

			out[velocity] = steps;
		}

		return out;
	}

	static function loudnesses():Vector<Int> {
		final out = new Vector<Int>(PSG_OFF + 1);

		out[0] = FULL;
		out[PSG_OFF] = 0;

		for (quiet in 1...PSG_OFF) {
			final much = Math.pow(10, -quiet * PSG_DECIBELS / 20);
			var want = Math.round(much * FULL);

			if (want < 1) want = 1;
			if (want > FULL) want = FULL;

			out[quiet] = want;
		}

		return out;
	}

	public static inline function bounded(velocity:Int):Int {
		return velocity < 0 ? 0 : (velocity > FULL ? FULL : velocity);
	}

	public static inline function attenuates(velocity:Int):Int {
		return FM[bounded(velocity)];
	}

	public static inline function quiets(velocity:Int):Int {
		return PSG[bounded(velocity)];
	}

	public static inline function scaled(velocity:Int, volume:Int):Int {
		if (volume >= FULL) return bounded(velocity);
		return bounded(Std.int(bounded(velocity) * volume / FULL));
	}

	public static inline function loudness(quiet:Int):Int {
		return LOUDNESS[quiet < 0 ? 0 : (quiet > PSG_OFF ? PSG_OFF : quiet)];
	}
}
