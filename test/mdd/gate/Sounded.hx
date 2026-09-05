package mdd.gate;

import haxe.ds.Vector;
import mdd.format.Pulse;
import mdd.play.Render;
import mdd.play.Stream;

@:unreflective
class Sounded {
	public static inline final WINDOW = 1024;
	public static inline final HOP = 256;
	public static inline final HEARD = 45.0;
	public static inline final SMOOTH = 24;

	public static function heard(stream:Stream, seconds:Float = HEARD):Vector<Float> {
		final want = Std.int(seconds * Pulse.TICKS);
		final render = new Render(Pulse.TICKS, Render.BLOCK);

		render.console = Render.CHIP;

		final mono = new Vector<Float>(want);
		var done = 0;

		while (done < want) {
			final took = render.serve(stream, done, Render.BLOCK, 0);
			if (took <= 0) break;

			for (index in 0...took) {
				final at = done + index;
				if (at >= want) break;

				mono[at] = (render.block[index * 2] + render.block[index * 2 + 1]) * 0.5;
			}

			done += took;
		}

		if (done > want) done = want;
		if (done < WINDOW * 4) return new Vector<Float>(0);

		final window = new Vector<Float>(WINDOW);

		for (index in 0...WINDOW) {
			window[index] = 0.5 - 0.5 * Math.cos(2 * Math.PI * index / (WINDOW - 1));
		}

		final fourier = new Fourier(WINDOW);
		final bins = WINDOW >> 1;

		final now = new Vector<Float>(bins);
		final before = new Vector<Float>(bins);

		for (index in 0...bins) before[index] = 0;

		final frames = Std.int((done - WINDOW) / HOP) + 1;
		final out:Array<Float> = [];

		for (frame in 0...frames) {
			final from = frame * HOP;

			fourier.clear();
			for (step in 0...WINDOW) fourier.real[step] = mono[from + step] * window[step];

			fourier.forward();
			fourier.magnitudes(now);

			var flux = 0.0;

			for (bin in 0...bins) {
				final gap = now[bin] - before[bin];
				if (gap > 0) flux += gap;

				before[bin] = now[bin];
			}

			out.push(frame == 0 ? 0 : flux);
		}

		return levelled(out);
	}

	static function levelled(held:Array<Float>):Vector<Float> {
		final many = held.length;
		final out = new Vector<Float>(many);

		for (index in 0...many) {
			var total = 0.0;
			var count = 0;

			final from = index - SMOOTH < 0 ? 0 : index - SMOOTH;
			final until = index + SMOOTH + 1 > many ? many : index + SMOOTH + 1;

			for (step in from...until) {
				total += held[step];
				count++;
			}

			final mean = count == 0 ? 0 : total / count;
			final gap = held[index] - mean;

			out[index] = gap > 0 ? gap : 0;
		}

		return out;
	}

	public static function paced(odf:Vector<Float>, fallback:Float):Float {
		if (odf.length < 64) return fallback;

		final quickest = 60.0 * Pulse.TICKS / (Pulse.MOST * Pulse.DIVISION * HOP);
		final slowest = 60.0 * Pulse.TICKS / (Pulse.LEAST * Pulse.DIVISION * HOP);

		final step = (slowest - quickest) / Pulse.STEPS;

		var best = 0.0;
		var most = -1.0;

		for (index in 0...Pulse.STEPS + 1) {
			final grid = quickest + index * step;
			final beats = 60.0 * Pulse.TICKS / (grid * Pulse.DIVISION * HOP);

			var real = 0.0;
			var side = 0.0;

			for (at in 0...odf.length) {
				final turn = 2 * Math.PI * at / grid;

				real += odf[at] * Math.cos(turn);
				side += odf[at] * Math.sin(turn);
			}

			final held = Math.sqrt(real * real + side * side) * likely(beats);

			if (held > most) {
				most = held;
				best = grid;
			}
		}

		if (best <= 0) return fallback;

		final beats = 60.0 * Pulse.TICKS / (best * Pulse.DIVISION * HOP);
		return beats < Pulse.LEAST || beats > Pulse.MOST ? fallback : Math.round(beats * 100) / 100;
	}

	static inline function likely(beats:Float):Float {
		final away = Math.log(beats / Pulse.MIDDLE) / Pulse.SPREAD;
		return Math.exp(-0.5 * away * away);
	}
}
