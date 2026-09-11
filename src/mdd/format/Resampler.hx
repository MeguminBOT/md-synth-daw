package mdd.format;

import haxe.ds.Vector;

@:unreflective

/**
	Changes the rate of a run of audio without folding what it cannot carry back into
	it.

	Taking one input sample in six and throwing the rest away is not resampling: every
	frequency above the new half rate comes back as a different one, and on a cymbal
	going from 48000 Hz to 11025 Hz that arrives as twelve decibels of rumble the
	recording never had. Anything above the new Nyquist has to be taken out before the
	rate changes, which is what the window here does.

	A run is read as silence past either end, so a window landing on the first or last
	few samples has only half of itself to work with and rejects far less there. That
	is a property of every filter at a boundary. It costs nothing on a hit that begins
	and ends in silence, and it is why a hit is better trimmed with a few milliseconds
	of lead in than cut exactly to its onset.

	This is an offline path. It allocates, and it is never called from the render
	thread.
**/
final class Resampler {
	/**
		How many input samples either side of an output one are read.

		A Blackman window this wide rejects what it is cutting by about seventy four
		decibels, which is already below the fifty three decibel floor eight bit samples
		carry, so nothing is gained by reading wider.
	**/
	public static inline final TAPS = 32;

	/**
		How far below the new half rate the cut sits, leaving the last few per cent of
		the band to fall away in rather than stopping on the edge of it.
	**/
	static inline final CUT = 0.46;

	/**
		Resamples a run of audio.

		@param held The audio, at plus or minus one.
		@param was The rate it is at, in hertz.
		@param want The rate to bring it to, in hertz.
		@return The audio at the new rate. The same run back where the two rates match,
			and an empty run where either rate is nought or nothing was given.
	**/
	public static function into(held:Vector<Float>, was:Int, want:Int):Vector<Float> {
		if (held.length == 0 || was < 1 || want < 1) return new Vector<Float>(0);
		if (was == want) return held;

		final ratio = want / was;
		final cut = ratio < 1 ? CUT * ratio : CUT;

		final many = Std.int(held.length * ratio);
		if (many < 1) return new Vector<Float>(0);

		final out = new Vector<Float>(many);
		final scale = 2.0 * cut;
		final span = TAPS * 2;

		for (index in 0...many) {
			final at = index / ratio;
			final base = Math.floor(at);

			var sum = 0.0;

			for (offset in -TAPS...TAPS + 1) {
				final reach = base + offset;
				final delta = at - reach;

				final turn = (delta + TAPS) / span;
				final window = 0.42 - 0.5 * Math.cos(2 * Math.PI * turn)
					+ 0.08 * Math.cos(4 * Math.PI * turn);

				final weight = sinc(scale * delta) * scale * window;

				final read = reach < 0 ? 0 : (reach >= held.length ? held.length - 1 : reach);
				sum += held[read] * weight;
			}

			out[index] = sum;
		}

		return out;
	}

	/**
		@param value Where to read it.
		@return `sin(pi x) / (pi x)`, and one at nought where that division is not
			defined.
	**/
	static inline function sinc(value:Float):Float {
		if (value == 0) return 1.0;

		final turn = Math.PI * value;
		return Math.sin(turn) / turn;
	}
}
