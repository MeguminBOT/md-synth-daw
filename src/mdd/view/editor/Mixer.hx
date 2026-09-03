package mdd.view.editor;

import haxe.ds.Vector;
import mdd.app.Session;
import mdd.song.Part;
import mdd.song.Song;
import mdd.ui.Colour;
import mdd.ui.Input;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective
final class Mixer extends Widget {
	public final session:Session;

	public final levels:Vector<Float> = new Vector<Float>(Part.COUNT);

	var hoverAt:Int = -1;
	var sliding:Int = -1;

	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;

		for (i in 0...Part.COUNT) levels[i] = 0;
	}

	public function stripWide():Float {
		return width / Part.COUNT;
	}

	public function stripAt(px:Float):Int {
		final at = Std.int((px - x) / stripWide());
		return at < 0 || at >= Part.COUNT ? -1 : at;
	}

	public function panTall():Float {
		final root = root();
		return root == null ? 20 : root.metrics.whole(20);
	}

	public function onPan(py:Float):Bool {
		final root = root();
		if (root == null) return false;

		final top = y + root.metrics.gap;
		return py >= top && py < top + panTall();
	}

	public function turned(at:Int):Void {
		final part:Part = at;
		if (!part.fm()) return;

		final held = session.song.pan[at];

		session.song.pan[at] = switch (held) {
			case Song.BOTH: Song.LEFT;
			case Song.LEFT: Song.RIGHT;
			case _: Song.BOTH;
		}

		session.say(part.name() + " " + sided(session.song.pan[at]));
		session.changed();
		invalidate();
	}

	public static function sided(pan:Int):String {
		return switch (pan) {
			case Song.LEFT: "L";
			case Song.RIGHT: "R";
			case _: "L R";
		}
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				final at = stripAt(event.x);
				if (at < 0) return false;

				final root = root();
				final metrics = root == null ? null : root.metrics;
				final part:Part = at;

				if (metrics != null && event.y > y + height - metrics.row) {
					session.song.muted[at] = !session.song.muted[at];
					session.changed();
					invalidate();
					return true;
				}

				if (onPan(event.y)) {
					session.choose(part);
					turned(at);
					return true;
				}

				session.choose(part);

				sliding = at;
				leaned(at, event.y);
				return true;

			case Kind.PointerUp:
				if (sliding < 0) return false;

				sliding = -1;
				return true;

			case Kind.PointerMove:
				if (sliding >= 0) {
					leaned(sliding, event.y);
					return true;
				}

				final at = stripAt(event.x);
				if (at == hoverAt) return false;

				hoverAt = at;
				invalidate();
				return true;

			case _:
		}

		return false;
	}

	public function throwAt(py:Float):Float {
		final root = root();
		final metrics = root == null ? null : root.metrics;
		final gap = metrics == null ? 6.0 : metrics.gap;
		final row = metrics == null ? 30.0 : metrics.row;
		final unit = metrics == null ? 4.0 : metrics.unit;

		final top = y + gap + panTall() + unit;
		final tall = height - gap * 2 - row - panTall() - unit;
		if (tall <= 0) return 1;

		final part = 1 - (py - top) / tall;
		return part < 0 ? 0 : (part > 1 ? 1 : part);
	}

	function leaned(at:Int, py:Float):Void {
		final want = Math.round(throwAt(py) * Song.LOUDEST);
		if (session.song.volume[at] == want) return;

		session.song.volume[at] = want;
		final part:Part = at;
		session.say(part.name() + " " + Math.round(want * 100 / Song.LOUDEST) + "%");
		session.changed();
		invalidate();
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
		final wide = stripWide();
		final small = metrics.small == null ? metrics.body : metrics.small;

		paint.rect(x, y, width, height, theme.panel);

		final head = y + metrics.gap;
		final top = head + panTall() + metrics.unit;
		final tall = height - metrics.gap * 2 - metrics.row - panTall() - metrics.unit;

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final left = x + index * wide;
			final colour = theme.part(index);
			final quiet = !session.song.audible(part);

			if (session.part.index() == index) {
				paint.rect(left, y, wide, height, theme.accent, Theme.SELECT);
			} else if (index == hoverAt) {
				paint.rect(left, y, wide, height, theme.accent, Theme.HOVER);
			}

			final track = metrics.whole(10);
			final middle = left + wide * 0.5;

			if (part.fm()) {
				paint.roundedRect(left + metrics.unit, head, wide - metrics.unit * 2,
					panTall(), metrics.radiusSmall, theme.raise1);
			}

			paint.roundedRect(middle - track * 0.5, top, track, tall, track * 0.5, theme.sink);

			final want = session.song.volume[index] / Song.LOUDEST;
			final knob = metrics.whole(4);
			final at = top + tall * (1 - want);

			paint.roundedRect(middle - track, at - knob * 0.5, track * 2, knob,
				metrics.radiusSmall, quiet ? theme.dim : theme.ink, index == sliding ? 1 : 0.85);

			final level = levels[index];
			final high = tall * (level > 1 ? 1 : level);

			if (high > 1) {
				paint.roundedRect(middle - track * 0.5, top + tall - high, track, high,
					track * 0.5, colour, quiet ? 0.3 : 1);
			}

			paint.roundedRect(left + metrics.unit, y + height - metrics.row + metrics.unit,
				wide - metrics.unit * 2, metrics.row - metrics.unit * 2, metrics.radiusSmall,
				quiet ? theme.raise1 : colour, quiet ? 1 : 0.35);
		}

		paint.reface(small);

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final left = x + index * wide;
			final quiet = !session.song.audible(part);

			paint.textCentred(part.name(), left + wide * 0.5,
				y + height - metrics.row + (metrics.row - small.height) * 0.5 + small.ascent,
				quiet ? theme.dim : theme.ink);

			if (!part.fm()) continue;

			paint.textCentred(sided(session.song.pan[index]), left + wide * 0.5,
				head + (panTall() - small.height) * 0.5 + small.ascent,
				session.song.pan[index] == Song.BOTH ? theme.dim : theme.accent, 0.95);
		}
	}
}
