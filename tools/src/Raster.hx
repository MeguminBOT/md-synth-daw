import haxe.io.Bytes;

class Raster {
	public static inline final SAMPLES = 5;

	public static function paint(svg:Svg, size:Int):Bytes {
		final out = Bytes.alloc(size * size * 4);
		final one:Array<Svg.Shape> = [];

		for (shape in svg.shapes) {
			one.resize(0);
			one.push(shape);

			final mask = covered(one, svg.width, svg.height, size);

			final red = (shape.colour >> 16) & 0xFF;
			final green = (shape.colour >> 8) & 0xFF;
			final blue = shape.colour & 0xFF;

			for (index in 0...size * size) {
				final cover = mask.get(index);
				if (cover == 0) continue;

				final at = index * 4;
				final over = cover / 255.0;
				final under = out.get(at + 3) / 255.0 * (1 - over);
				final total = over + under;

				if (total <= 0) continue;

				out.set(at, Std.int((red * over + out.get(at) * under) / total));
				out.set(at + 1, Std.int((green * over + out.get(at + 1) * under) / total));
				out.set(at + 2, Std.int((blue * over + out.get(at + 2) * under) / total));
				out.set(at + 3, Std.int(total * 255));
			}
		}

		return out;
	}

	public static function fill(svg:Svg, size:Int):Bytes {
		return covered(svg.shapes, svg.width, svg.height, size);
	}

	static function covered(shapes:Array<Svg.Shape>, wide:Float, high:Float, size:Int):Bytes {
		final out = Bytes.alloc(size * size);
		final tall = size * SAMPLES;

		final sums = new Array<Int>();
		sums.resize(size * size);
		for (index in 0...sums.length) sums[index] = 0;

		final scale = wide <= 0 ? 1 : size / wide;
		final down = high <= 0 ? 1 : size / high;

		final crossings:Array<Float> = [];
		final winding:Array<Int> = [];

		for (shape in shapes) {
			final weight = shape.alpha <= 0 ? 0 : (shape.alpha >= 1 ? 1.0 : shape.alpha);
			if (weight <= 0) continue;

			for (row in 0...tall) {
				final y = (row + 0.5) / SAMPLES / down;

				crossings.resize(0);
				winding.resize(0);

				for (contour in shape.contours) {
					final points = contour.points;
					final many = points.length >> 1;
					if (many < 3) continue;

					var ax = points[(many - 1) * 2];
					var ay = points[(many - 1) * 2 + 1];

					for (index in 0...many) {
						final bx = points[index * 2];
						final by = points[index * 2 + 1];

						if ((ay <= y && by > y) || (by <= y && ay > y)) {
							final t = (y - ay) / (by - ay);

							crossings.push(ax + t * (bx - ax));
							winding.push(by > ay ? 1 : -1);
						}

						ax = bx;
						ay = by;
					}
				}

				if (crossings.length < 2) continue;

				sort(crossings, winding);
				span(sums, size, row, crossings, winding, shape.evenOdd, scale, weight);
			}
		}

		final most = SAMPLES * SAMPLES;

		for (index in 0...sums.length) {
			var held = Std.int(sums[index] / most);
			if (held > 255) held = 255;
			out.set(index, held);
		}

		return out;
	}

	static function span(sums:Array<Int>, size:Int, row:Int, crossings:Array<Float>,
			winding:Array<Int>, evenOdd:Bool, scale:Float, weight:Float):Void {
		final line = Std.int(row / SAMPLES) * size;
		var count = 0;

		for (index in 0...crossings.length - 1) {
			count += evenOdd ? 1 : winding[index];

			final inside = evenOdd ? (count & 1) != 0 : count != 0;
			if (!inside) continue;

			var from = crossings[index] * scale * SAMPLES;
			var until = crossings[index + 1] * scale * SAMPLES;

			if (until <= from) continue;
			if (until <= 0 || from >= size * SAMPLES) continue;

			if (from < 0) from = 0;
			if (until > size * SAMPLES) until = size * SAMPLES;

			var at = Std.int(from);
			final last = Std.int(Math.ceil(until));

			while (at < last) {
				final left = at > from ? at : from;
				final right = (at + 1) < until ? (at + 1) : until;
				final much = right - left;

				if (much > 0) {
					final cell = line + Std.int(at / SAMPLES);
					if (cell >= 0 && cell < sums.length) {
						sums[cell] += Std.int(much * 255 * weight);
					}
				}

				at++;
			}
		}
	}

	static function sort(crossings:Array<Float>, winding:Array<Int>):Void {
		for (index in 1...crossings.length) {
			final held = crossings[index];
			final wind = winding[index];
			var at = index - 1;

			while (at >= 0 && crossings[at] > held) {
				crossings[at + 1] = crossings[at];
				winding[at + 1] = winding[at];
				at--;
			}

			crossings[at + 1] = held;
			winding[at + 1] = wind;
		}
	}
}
