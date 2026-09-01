package mdd.view;

import haxe.ds.Vector;
import mdd.song.Part;
import mdd.ui.Colour;
import mdd.ui.Input;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective
final class ChannelRack extends Widget {
	public final session:Session;

	public final levels:Vector<Float> = new Vector<Float>(Part.COUNT);

	var hoverAt:Int = -1;

	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;

		for (i in 0...Part.COUNT) levels[i] = 0;
	}

	public function rowHeight():Float {
		final root = root();
		return root == null ? 30 : root.metrics.row;
	}

	public function rowAt(py:Float):Int {
		final at = Std.int((py - y - header()) / rowHeight());
		return at < 0 || at >= Part.COUNT ? -1 : at;
	}

	function header():Float {
		final root = root();
		return root == null ? 22 : root.metrics.whole(22);
	}

	override function took(event:Input):Bool {
		final root = root();
		if (root == null) return false;

		switch (event.kind) {
			case Kind.PointerDown:
				final at = rowAt(event.y);
				if (at < 0) return false;

				final metrics = root.metrics;
				final part:Part = at;

				if (event.x >= x + width - metrics.whole(96)
						&& event.x < x + width - metrics.whole(72)) {
					session.song.muted[at] = !session.song.muted[at];
					session.changed();
					invalidate();
					return true;
				}

				if (event.x >= x + width - metrics.whole(72)
						&& event.x < x + width - metrics.whole(48)) {
					session.song.soloed[at] = !session.song.soloed[at];
					session.changed();
					invalidate();
					return true;
				}

				session.choose(part);
				invalidate();
				return true;

			case Kind.PointerMove:
				final at = rowAt(event.y);
				if (at == hoverAt) return false;
				hoverAt = at;
				invalidate();
				return true;

			case _:
		}

		return false;
	}

	override function hovered(on:Bool):Void {
		if (!on) hoverAt = -1;
		super.hovered(on);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final font = metrics.body;
		final small = metrics.small == null ? font : metrics.small;
		final tall = rowHeight();
		final top = header();

		paint.rect(x, y, width, height, theme.panel);
		paint.reface(small);
		paint.text("CHANNEL RACK", x + metrics.inset, y + top * 0.5 + small.ascent * 0.5,
			theme.dim, 0.8);

		final swatch = metrics.whole(10);

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final row = y + top + index * tall;

			if (session.part.index() == index) {
				paint.roundedRect(x + metrics.unit, row + 1, width - metrics.unit * 2, tall - 2,
					metrics.radiusRow, theme.accent, Theme.SELECT);
			} else if (index == hoverAt) {
				paint.roundedRect(x + metrics.unit, row + 1, width - metrics.unit * 2, tall - 2,
					metrics.radiusRow, theme.accent, Theme.HOVER);
			}

			final quiet = !session.song.audible(part);

			paint.roundedRect(x + metrics.inset, row + (tall - swatch) * 0.5, swatch, swatch,
				metrics.radiusSmall, theme.part(index), quiet ? 0.25 : 1);

			mark(paint, theme, metrics, x + width - metrics.whole(96), row, tall,
				session.song.muted[index]);
			mark(paint, theme, metrics, x + width - metrics.whole(72), row, tall,
				session.song.soloed[index]);

			meter(paint, theme, metrics, x + width - metrics.whole(44), row, tall, index,
				theme.part(index));
		}

		paint.reface(small);

		for (index in 0...Part.COUNT) {
			final row = y + top + index * tall;
			final line = row + (tall - small.height) * 0.5 + small.ascent;
			final size = metrics.whole(18);

			paint.textCentred("M", x + width - metrics.whole(96) + size * 0.5, line,
				session.song.muted[index] ? theme.ink : theme.dim);
			paint.textCentred("S", x + width - metrics.whole(72) + size * 0.5, line,
				session.song.soloed[index] ? theme.ink : theme.dim);

			final instrument = session.song.instrumentAt(session.song.rack[index]);
			if (instrument == null) continue;

			paint.text(instrument.name, x + metrics.inset + swatch + metrics.gap
				+ metrics.whole(48), line, theme.dim, 0.7);
		}

		paint.reface(font);

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final row = y + top + index * tall;
			final quiet = !session.song.audible(part);

			paint.text(part.name(), x + metrics.inset + swatch + metrics.gap,
				row + (tall - font.height) * 0.5 + font.ascent,
				quiet ? theme.dim : theme.ink, quiet ? 0.5 : 1);
		}
	}

	function mark(paint:Paint, theme:Theme, metrics:Metrics, at:Float, row:Float, tall:Float,
			on:Bool):Void {
		final size = metrics.whole(18);
		final top = row + (tall - size) * 0.5;

		paint.roundedRect(at, top, size, size, metrics.radiusSmall,
			on ? theme.accent : theme.raise1, on ? 0.8 : 1);
	}

	function meter(paint:Paint, theme:Theme, metrics:Metrics, at:Float, row:Float, tall:Float,
			index:Int, colour:Colour):Void {
		final wide = metrics.whole(32);
		final high = metrics.whole(6);
		final top = row + (tall - high) * 0.5;

		paint.roundedRect(at, top, wide, high, high * 0.5, theme.sink);

		final level = levels[index];
		if (level <= 0.002) return;

		final filled = wide * (level > 1 ? 1 : level);
		paint.roundedRect(at, top, filled, high, high * 0.5, colour);
	}
}
