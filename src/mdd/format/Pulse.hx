package mdd.format;

import mdd.play.Stream;

@:unreflective
final class Pulse {
	public static inline final TICKS = 44100;

	public static inline final LEAST = 60.0;
	public static inline final MOST = 220.0;
	public static inline final MIDDLE = 120.0;
	public static inline final SPREAD = 0.5;

	public static inline final DIVISION = 4;
	public static inline final STEPS = 1200;
	public static inline final TOLERANCE = 0.12;

	static inline final ENOUGH = 32;

	public static function of(stream:Stream, rate:Int, fallback:Float):Float {
		return from(struck(stream, rate), fallback);
	}

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

	public static inline final OFFSETS = 400;

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

	public static inline final FINE = 200;

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

	static inline function likely(beats:Float):Float {
		final away = Math.log(beats / MIDDLE) / SPREAD;
		return Math.exp(-0.5 * away * away);
	}

	static inline function round(beats:Float):Float {
		return Math.round(beats * 100) / 100;
	}
}
