package mdd.gate;

import haxe.ds.Vector;

@:unreflective
final class Fourier {
	public var size(default, null):Int;

	final cosines:Vector<Float>;
	final sines:Vector<Float>;
	final reversed:Vector<Int>;

	public final real:Vector<Float>;
	public final imaginary:Vector<Float>;

	public function new(size:Int) {
		this.size = size;

		real = new Vector<Float>(size);
		imaginary = new Vector<Float>(size);

		cosines = new Vector<Float>(size >> 1);
		sines = new Vector<Float>(size >> 1);

		for (index in 0...size >> 1) {
			final turn = -2 * Math.PI * index / size;

			cosines[index] = Math.cos(turn);
			sines[index] = Math.sin(turn);
		}

		reversed = new Vector<Int>(size);

		var bits = 0;
		while ((1 << bits) < size) bits++;

		for (index in 0...size) {
			var held = index;
			var out = 0;

			for (step in 0...bits) {
				out = (out << 1) | (held & 1);
				held >>= 1;
			}

			reversed[index] = out;
		}
	}

	public function forward():Void {
		for (index in 0...size) {
			final other = reversed[index];
			if (other <= index) continue;

			final oneReal = real[index];
			final oneSide = imaginary[index];

			real[index] = real[other];
			imaginary[index] = imaginary[other];

			real[other] = oneReal;
			imaginary[other] = oneSide;
		}

		var span = 2;

		while (span <= size) {
			final half = span >> 1;
			final stride = size / span;

			var start = 0;

			while (start < size) {
				var turn = 0;

				for (index in 0...half) {
					final here = start + index;
					final there = here + half;

					final cosine = cosines[turn];
					final sine = sines[turn];

					final thereReal = real[there] * cosine - imaginary[there] * sine;
					final thereSide = real[there] * sine + imaginary[there] * cosine;

					real[there] = real[here] - thereReal;
					imaginary[there] = imaginary[here] - thereSide;

					real[here] += thereReal;
					imaginary[here] += thereSide;

					turn += Std.int(stride);
				}

				start += span;
			}

			span <<= 1;
		}
	}

	public function magnitudes(into:Vector<Float>):Void {
		final bins = size >> 1;

		for (index in 0...bins) {
			final one = real[index];
			final two = imaginary[index];

			into[index] = Math.sqrt(one * one + two * two);
		}
	}

	public function clear():Void {
		for (index in 0...size) {
			real[index] = 0;
			imaginary[index] = 0;
		}
	}
}
