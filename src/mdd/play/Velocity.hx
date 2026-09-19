package mdd.play;

import haxe.ds.Vector;

/**
	Velocity to attenuation, for both parts, and back again.

	The two parts step by different amounts, three quarters of a decibel on the FM part
	and two on the squares, so a velocity does not mean the same number on each. The
	tables are built once from those step sizes rather than tuned by ear.
**/
@:unreflective
final class Velocity {
	/**
		The loudest velocity, matching MIDI.
	**/
	public static inline final FULL = 127;

	/**
		The FM total level that is silence.
	**/
	static inline final SILENT = 127;

	/**
		The square attenuation that is silence.
	**/
	public static inline final PSG_OFF = 15;

	/**
		What one step of FM total level is worth.
	**/
	static inline final FM_DECIBELS = 0.75;

	/**
		What one step of square attenuation is worth.
	**/
	static inline final PSG_DECIBELS = 2.0;

	/**
		Velocity to FM total level.
	**/
	static final FM:Vector<Int> = attenuations(FM_DECIBELS, SILENT);

	/**
		Velocity to square attenuation.
	**/
	static final PSG:Vector<Int> = attenuations(PSG_DECIBELS, PSG_OFF);

	/**
		Square attenuation back to a velocity, for reading an import.
	**/
	static final LOUDNESS:Vector<Int> = loudnesses();

	/**
		Builds a velocity to attenuation table for one part.

		@param decibels What one step of that attenuation is worth.
		@param most The attenuation value that is silence.
		@return One attenuation per velocity from 0 to 127.
	**/
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

	/**
		Builds the table that reads a square attenuation back as a velocity.

		@return One velocity per attenuation step.
	**/
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

	/**
		@param velocity Any number.
		@return It held to 0 to 127.
	**/
	public static inline function bounded(velocity:Int):Int {
		return velocity < 0 ? 0 : (velocity > FULL ? FULL : velocity);
	}

	/**
		@param velocity A velocity, 0 to 127.
		@return The FM total level it corresponds to.
	**/
	public static inline function attenuates(velocity:Int):Int {
		return FM[bounded(velocity)];
	}

	/**
		@param velocity A velocity, 0 to 127.
		@return The square attenuation it corresponds to.
	**/
	public static inline function quiets(velocity:Int):Int {
		return PSG[bounded(velocity)];
	}

	/**
		Applies a channel volume to a note velocity.

		@param velocity The note velocity, 0 to 127.
		@param volume The channel volume, 0 to 127.
		@return The velocity the note should actually sound at.
	**/
	public static inline function scaled(velocity:Int, volume:Int):Int {
		if (volume >= FULL) return bounded(velocity);
		return bounded(Std.int(bounded(velocity) * volume / FULL));
	}

	/**
		@param quiet A square attenuation, 0 to 15.
		@return The velocity that attenuation reads back as.
	**/
	public static inline function loudness(quiet:Int):Int {
		return LOUDNESS[quiet < 0 ? 0 : (quiet > PSG_OFF ? PSG_OFF : quiet)];
	}
}
