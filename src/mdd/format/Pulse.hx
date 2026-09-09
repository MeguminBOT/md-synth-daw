package mdd.format;

import mdd.play.Stream;

@:unreflective

/**
	Finds the tempo of a register stream by looking at where notes actually begin.

	An imported file carries no tempo, only writes at sample positions. Guessing one
	lets the piece land on a grid a person can edit, and the timing is still kept as
	the file wrote it, so the guess changes what is drawn and never what is heard.
**/
final class Pulse {
	/**
		The rate positions are measured in.
	**/
	public static inline final TICKS = 44100;

	/**
		The slowest tempo considered.
	**/
	public static inline final LEAST = 60.0;

	/**
		The fastest tempo considered.
	**/
	public static inline final MOST = 220.0;

	/**
		Where the search starts.
	**/
	public static inline final MIDDLE = 120.0;

	/**
		How far either side of a candidate a beat may fall and still count.
	**/
	public static inline final SPREAD = 0.5;

	/**
		How many grid positions a beat is divided into.
	**/
	public static inline final DIVISION = 4;

	/**
		How many tempos are tried.
	**/
	public static inline final STEPS = 1200;

	/**
		How far off the grid an onset may be and still count as on it.
	**/
	public static inline final TOLERANCE = 0.12;

	static inline final ENOUGH = 32;

	/**
		Finds the tempo of a register stream.

		@param stream The stream to read.
		@param rate The rate its positions are in.
		@param fallback What to answer where nothing sounds.
		@return The tempo in beats a minute.
	**/
	public static function of(stream:Stream, rate:Int, fallback:Float):Float {
		return from(struck(stream, rate), fallback);
	}

	/**
		Finds where notes begin, which is what a tempo is fitted to.

		@param stream The stream to read.
		@param rate The rate its positions are in.
		@return Every onset, in ticks, in order.
	**/
	public static function struck(stream:Stream, rate:Int):Array<Int> {
		final out:Array<Int> = [];
		final apart = Std.int(TICKS * 2.0 / (rate < 1 ? 60 : rate));

		final quiet = new haxe.ds.Vector<Int>(4);
		for (index in 0...4) quiet[index] = 15;

		var half = 0;
		var address = -1;

		for (index in 0...stream.count) {
			final at = stream.tickAt(index);
			final port = stream.portAt(index);
			final value = stream.valueAt(index);

			var struck = false;

			if (stream.kindAt(index) == Stream.PSG) {
				if ((value & 0x90) != 0x90) continue;

				final channel = (value >> 5) & 3;
				final level = value & 15;

				struck = quiet[channel] == 15 && level < 15;
				quiet[channel] = level;
			} else if ((port & 1) == 0) {
				half = (port >> 1) & 1;
				address = value;

				continue;
			} else {
				if (address < 0 || half != 0 || address != 0x28) continue;
				if ((value & 3) == 3) continue;

				struck = (value & 0xF0) != 0;
			}

			if (!struck) continue;
			if (out.length > 0 && at - out[out.length - 1] <= apart) continue;

			out.push(at);
		}

		return out;
	}

	/**
		Fits a tempo to a set of onsets by trying every candidate and keeping the best.

		@param onsets Where notes begin, in ticks.
		@param fallback What to answer where there are too few onsets.
		@return The tempo in beats a minute.
	**/
	public static function from(onsets:Array<Int>, fallback:Float):Float {
		if (onsets.length < ENOUGH) return fallback;

		final quickest = 60.0 * TICKS / (MOST * DIVISION);
		final slowest = 60.0 * TICKS / (LEAST * DIVISION);

		final step = (slowest - quickest) / STEPS;

		var best = 0.0;
		var most = -1.0;

		for (index in 0...STEPS + 1) {
			final grid = quickest + index * step;
			final beats = 60.0 * TICKS / (grid * DIVISION);

			final held = tight(onsets, grid) * likely(beats);

			if (held > most) {
				most = held;
				best = grid;
			}
		}

		if (best <= 0) return fallback;

		best = sharpened(onsets, best, step);

		final beats = 60.0 * TICKS / (best * DIVISION);
		if (beats < LEAST || beats > MOST) return fallback;

		return fits(onsets, beats) > fits(onsets, fallback) ? round(beats) : fallback;
	}

	/**
		How many phases of the grid are tried against a candidate tempo.
	**/
	public static inline final OFFSETS = 400;

	/**
		Finds where the grid should start for a tempo already chosen.

		@param onsets Where notes begin, in ticks.
		@param beats The tempo.
		@return The offset in ticks that fits the onsets best.
	**/
	public static function phase(onsets:Array<Int>, beats:Float):Float {
		if (beats <= 0 || onsets.length == 0) return 0;

		final grid = 60.0 * TICKS / (beats * DIVISION);
		if (grid <= 0) return 0;

		var best = 0.0;
		var most = -1;

		for (step in 0...OFFSETS) {
			final shift = grid * step / OFFSETS;
			var near = 0;

			for (at in onsets) {
				final away = (at - shift) / grid;
				final gap = away - Math.round(away);

				if ((gap < 0 ? -gap : gap) <= TOLERANCE) near++;
			}

			if (near > most) {
				most = near;
				best = shift;
			}
		}

		return best;
	}

	/**
		@param onsets Where notes begin, in ticks.
		@param beats A candidate tempo.
		@return How well the onsets fall on that grid, higher being better.
	**/
	public static function fits(onsets:Array<Int>, beats:Float):Float {
		if (beats <= 0 || onsets.length == 0) return 0;

		final grid = 60.0 * TICKS / (beats * DIVISION);
		if (grid <= 0) return 0;

		var real = 0.0;
		var side = 0.0;

		for (at in onsets) {
			final turn = 2 * Math.PI * at / grid;

			real += Math.cos(turn);
			side += Math.sin(turn);
		}

		final phase = Math.atan2(side, real) / (2 * Math.PI) * grid;

		var near = 0;

		for (at in onsets) {
			final away = (at - phase) / grid;
			final gap = away - Math.round(away);

			if ((gap < 0 ? -gap : gap) <= TOLERANCE) near++;
		}

		return near / onsets.length;
	}

	/**
		How many refinements are tried around a fit.
	**/
	public static inline final FINE = 200;

	/**
		Refines a grid by trying small changes either side of it.

		@param onsets Where notes begin, in ticks.
		@param grid The grid so far, in ticks per division.
		@param step How far to move it each try.
		@return The best grid found.
	**/
	static function sharpened(onsets:Array<Int>, grid:Float, step:Float):Float {
		var best = grid;
		var most = tight(onsets, grid);

		final from = grid - step;
		final fine = step * 2 / FINE;

		for (index in 0...FINE + 1) {
			final tried = from + index * fine;
			if (tried <= 0) continue;

			final held = tight(onsets, tried);

			if (held > most) {
				most = held;
				best = tried;
			}
		}

		return best;
	}

	/**
		@param onsets Where notes begin, in ticks.
		@param grid A grid, in ticks per division.
		@return How closely the onsets sit to it, higher being better.
	**/
	static function tight(onsets:Array<Int>, grid:Float):Float {
		var real = 0.0;
		var side = 0.0;

		for (at in onsets) {
			final turn = 2 * Math.PI * at / grid;

			real += Math.cos(turn);
			side += Math.sin(turn);
		}

		return Math.sqrt(real * real + side * side) / onsets.length;
	}

	/**
		@param beats A candidate tempo.
		@return How much to favour it, which pulls the answer towards the tempos music actually uses
			rather than a multiple of the right one.
	**/
	static inline function likely(beats:Float):Float {
		final away = Math.log(beats / MIDDLE) / SPREAD;
		return Math.exp(-0.5 * away * away);
	}

	/**
		@param beats A tempo.
		@return It snapped to a whole or a half beat where it is nearly one.
	**/
	static inline function round(beats:Float):Float {
		return Math.round(beats * 100) / 100;
	}
}
