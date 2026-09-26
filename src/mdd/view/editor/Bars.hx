package mdd.view.editor;

import mdd.ui.Colour;
import mdd.ui.Paint;

@:unreflective

/**
	The shading every other bar gets behind a timeline. The roll, the playlist and the lanes draw it
	the same way, so the three line up where they sit one above the other.
**/
final class Bars {
	/**
		How strongly every other bar is lightened, so where one bar ends and the next begins can be
		seen at any zoom.
	**/
	public static inline final SHADE = 0.035;

	/**
		Shades every other bar between two edges, on a timeline where a tick lands at
		`origin + tick * perTick - offset`.

		@param paint Where to draw.
		@param ink What to shade with.
		@param bar How long a bar is, in ticks.
		@param reach The tick the shading stops at.
		@param origin Where tick nought lands, across, before the timeline is scrolled.
		@param offset How far the timeline is scrolled, across.
		@param perTick How wide one tick is.
		@param left Where the shading starts, across.
		@param right Where it stops.
		@param top Where it starts, down.
		@param tall How tall it is.
	**/
	public static function shade(paint:Paint, ink:Colour, bar:Int, reach:Int, origin:Float,
			offset:Float, perTick:Float, left:Float, right:Float, top:Float, tall:Float):Void {
		var at = Std.int(Math.round((left - origin + offset) / perTick) / bar) * bar;
		if (at < 0) at = 0;

		while (at < reach) {
			final from = origin + at * perTick - offset;
			if (from > right) break;

			if (Std.int(at / bar) % 2 == 1) {
				final start = from < left ? left : from;
				final ends = origin + (at + bar) * perTick - offset;

				paint.rect(start, top, (ends > right ? right : ends) - start, tall, ink, SHADE);
			}

			at += bar;
		}
	}
}
