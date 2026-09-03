package mdd.ui;

import haxe.ds.Vector;

@:unreflective
final class Glyph {
	public static inline final DOT = 0;
	public static inline final RING = 1;
	public static inline final SQUARE = 2;
	public static inline final DIAMOND = 3;
	public static inline final TRIANGLE = 4;
	public static inline final WAVE = 5;
	public static inline final PULSE = 6;
	public static inline final SAW = 7;
	public static inline final BARS = 8;
	public static inline final CROSS = 9;
	public static inline final SHAPES = 10;

	public static inline final PIANO = 10;
	public static inline final GRAND = 11;
	public static inline final GUITAR = 12;
	public static inline final ELECTRIC = 13;
	public static inline final BASS = 14;
	public static inline final STRINGS = 15;
	public static inline final BRASS = 16;
	public static inline final ORGAN = 17;
	public static inline final FLUTE = 18;
	public static inline final VOICE = 19;
	public static inline final BELL = 20;
	public static inline final DRUM = 21;
	public static inline final SNARE = 22;
	public static inline final CYMBAL = 23;
	public static inline final COUNT = 24;

	public static final NAMES:Array<String> = [
		"dot", "ring", "square", "diamond", "triangle", "wave",
		"pulse", "saw", "bars", "cross",
		"piano", "grand piano", "acoustic guitar", "electric guitar", "bass guitar",
		"strings", "brass", "organ", "flute", "voice", "bell", "drum", "snare", "cymbal"
	];

	final points:Vector<Float> = new Vector<Float>(32);

	public function new() {}

	public function draw(paint:Paint, which:Int, cx:Float, cy:Float, size:Float, colour:Colour,
			ground:Colour, alpha:Float = 1):Void {
		final half = size * 0.5;
		final hair = size * 0.13 < 1 ? 1 : size * 0.13;

		switch (which) {
			case RING:
				paint.ring(cx, cy, half * 0.86, hair, colour, alpha);

			case SQUARE:
				paint.rect(cx - half * 0.82, cy - half * 0.82, size * 0.82, size * 0.82, colour,
					alpha);

			case DIAMOND:
				points[0] = cx;
				points[1] = cy - half;
				points[2] = cx + half;
				points[3] = cy;
				points[4] = cx;
				points[5] = cy + half;
				points[6] = cx - half;
				points[7] = cy;
				paint.polygon(points, 4, colour, alpha);

			case TRIANGLE:
				points[0] = cx;
				points[1] = cy - half;
				points[2] = cx + half;
				points[3] = cy + half * 0.8;
				points[4] = cx - half;
				points[5] = cy + half * 0.8;
				paint.polygon(points, 3, colour, alpha);

			case WAVE:
				for (step in 0...7) {
					points[step * 2] = cx - half + size * step / 6;
					points[step * 2 + 1] = cy - Math.sin(step * Math.PI / 3) * half * 0.8;
				}
				paint.polyline(points, 7, hair, colour, alpha);

			case PULSE:
				points[0] = cx - half;
				points[1] = cy + half * 0.8;
				points[2] = cx - half;
				points[3] = cy - half * 0.8;
				points[4] = cx;
				points[5] = cy - half * 0.8;
				points[6] = cx;
				points[7] = cy + half * 0.8;
				points[8] = cx + half;
				points[9] = cy + half * 0.8;
				points[10] = cx + half;
				points[11] = cy - half * 0.8;
				paint.polyline(points, 6, hair, colour, alpha);

			case SAW:
				points[0] = cx - half;
				points[1] = cy + half * 0.8;
				points[2] = cx + half;
				points[3] = cy - half * 0.8;
				points[4] = cx + half;
				points[5] = cy + half * 0.8;
				paint.polyline(points, 3, hair, colour, alpha);

			case BARS:
				final wide = size * 0.22;
				paint.rect(cx - half, cy - half * 0.5, wide, size * 0.5, colour, alpha);
				paint.rect(cx - wide * 0.5, cy - half, wide, size, colour, alpha);
				paint.rect(cx + half - wide, cy - half * 0.75, wide, size * 0.75, colour, alpha);

			case CROSS:
				paint.rect(cx - half, cy - hair * 0.5, size, hair, colour, alpha);
				paint.rect(cx - hair * 0.5, cy - half, hair, size, colour, alpha);

			case PIANO:
				final wide = size * 0.26;
				paint.rect(cx - half, cy - half, wide, size, colour, alpha * 0.5);
				paint.rect(cx - wide * 0.5, cy - half, wide, size * 0.62, colour, alpha);
				paint.rect(cx + half - wide, cy - half, wide, size, colour, alpha * 0.5);

			case GRAND:
				points[0] = cx - half;
				points[1] = cy - half;
				points[2] = cx + half * 0.3;
				points[3] = cy - half;
				points[4] = cx + half;
				points[5] = cy - half * 0.1;
				points[6] = cx + half;
				points[7] = cy;
				points[8] = cx - half;
				points[9] = cy;
				paint.polygon(points, 5, colour, alpha * 0.8);
				paint.rect(cx - half, cy + half * 0.3, size, size * 0.35, colour, alpha);

			case GUITAR:
				paint.rect(cx - hair * 0.6, cy - half, hair * 1.2, size * 0.5, colour, alpha);
				paint.rect(cx - hair * 1.5, cy - half, hair * 3, size * 0.11, colour, alpha);
				paint.circle(cx, cy + half * 0.36, half * 0.64, colour, alpha);
				paint.circle(cx, cy + half * 0.2, hair * 0.9, ground, alpha);

			case ELECTRIC:
				paint.rect(cx - hair * 0.6, cy - half, hair * 1.2, size * 0.52, colour, alpha);
				paint.rect(cx - hair * 1.8, cy - half, hair * 3.6, size * 0.12, colour, alpha);
				paint.roundedRect(cx - half * 0.85, cy + half * 0.05, size * 0.85, size * 0.5,
					half * 0.3, colour, alpha);
				paint.rect(cx - half * 0.55, cy + half * 0.45, size * 0.55, hair * 0.9, colour,
					alpha * 0.35);

			case BASS:
				paint.rect(cx - hair * 0.6, cy - half, hair * 1.2, size * 0.68, colour, alpha);
				paint.rect(cx - hair * 2.6, cy - half, hair * 5.2, size * 0.15, colour, alpha);
				paint.roundedRect(cx - half * 0.62, cy + half * 0.36, size * 0.62, size * 0.34,
					half * 0.26, colour, alpha);

			case STRINGS:
				paint.rect(cx - hair * 0.5, cy - half, hair, size * 0.42, colour, alpha);
				paint.ring(cx, cy - half + hair, hair * 1.2, hair * 0.8, colour, alpha);
				paint.ring(cx, cy + half * 0.35, half * 0.55, hair, colour, alpha);
				paint.line(cx - half, cy + half * 0.9, cx + half, cy - half * 0.1, hair * 0.8,
					colour, alpha * 0.7);

			case BRASS:
				paint.rect(cx - half * 0.8, cy - hair * 0.7, size * 0.68, hair * 1.4, colour,
					alpha);
				paint.ring(cx - half * 0.85, cy, hair * 1.4, hair * 0.9, colour, alpha);

				points[0] = cx + half * 0.12;
				points[1] = cy - hair * 1.8;
				points[2] = cx + half;
				points[3] = cy - half * 0.85;
				points[4] = cx + half;
				points[5] = cy + half * 0.85;
				points[6] = cx + half * 0.12;
				points[7] = cy + hair * 1.8;
				paint.polygon(points, 4, colour, alpha);

				for (step in 0...2) {
					paint.rect(cx - half * 0.35 + step * half * 0.34, cy - half * 0.6,
						hair * 0.8, size * 0.3, colour, alpha);
				}

			case ORGAN:
				final wide = size * 0.24;
				pipe(paint, cx - half + wide * 0.5, cy, wide, size * 0.62, colour, alpha);
				pipe(paint, cx, cy, wide, size, colour, alpha);
				pipe(paint, cx + half - wide * 0.5, cy, wide, size * 0.8, colour, alpha);

			case FLUTE:
				paint.roundedRect(cx - half, cy - hair * 1.4, size, hair * 2.8, hair, colour,
					alpha);

				for (step in 0...3) {
					paint.circle(cx - half * 0.25 + step * half * 0.45, cy, hair * 0.7, ground,
						alpha);
				}

			case VOICE:
				paint.circle(cx, cy - half * 0.4, half * 0.4, colour, alpha);
				paint.arc(cx, cy + half * 0.95, half * 0.8, Math.PI, Math.PI * 2, hair * 1.6,
					colour, alpha);

			case BELL:
				points[0] = cx - half * 0.8;
				points[1] = cy + half * 0.5;
				points[2] = cx - half * 0.45;
				points[3] = cy - half * 0.25;
				points[4] = cx;
				points[5] = cy - half * 0.8;
				points[6] = cx + half * 0.45;
				points[7] = cy - half * 0.25;
				points[8] = cx + half * 0.8;
				points[9] = cy + half * 0.5;
				paint.polygon(points, 5, colour, alpha);
				paint.circle(cx, cy + half * 0.8, hair * 0.9, colour, alpha);

			case DRUM:
				paint.circle(cx, cy, half * 0.92, colour, alpha);
				paint.circle(cx, cy, half * 0.52, ground, alpha);
				paint.circle(cx, cy, half * 0.2, colour, alpha);

			case SNARE:
				paint.rect(cx - half, cy - half * 0.6, size, size * 0.7, colour, alpha);
				paint.rect(cx - half * 0.9, cy - half * 0.3, size * 0.9, hair * 0.9, ground,
					alpha);
				paint.rect(cx - half * 0.9, cy + half * 0.15, size * 0.9, hair * 0.9, ground,
					alpha);

			case CYMBAL:
				points[0] = cx - half;
				points[1] = cy - half * 0.1;
				points[2] = cx;
				points[3] = cy - half * 0.5;
				points[4] = cx + half;
				points[5] = cy - half * 0.1;
				points[6] = cx;
				points[7] = cy + half * 0.15;
				paint.polygon(points, 4, colour, alpha);
				paint.rect(cx - hair * 0.5, cy - half * 0.1, hair, size * 0.55, colour,
					alpha * 0.6);

			case _:
				paint.circle(cx, cy, half, colour, alpha);
		}
	}

	function pipe(paint:Paint, cx:Float, cy:Float, wide:Float, tall:Float, colour:Colour,
			alpha:Float):Void {
		final half = wide * 0.5;
		final base = cy + tall * 0.5;

		paint.rect(cx - half, base - tall + half, wide, tall - half, colour, alpha);
		paint.circle(cx, base - tall + half, half, colour, alpha);
	}
}
