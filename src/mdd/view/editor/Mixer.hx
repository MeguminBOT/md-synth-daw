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

	public static inline final MASTER = 0;
	public static inline final FIRST = 1;
	public static inline final STRIPS = Part.COUNT + 1;

	public final levels:Vector<Float> = new Vector<Float>(Part.COUNT);

	public var onMaster:Null<Int -> Void> = null;

	var hoverAt:Int = -1;
	var sliding:Int = -1;
	var output:Float = 0;

	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;

		for (i in 0...Part.COUNT) levels[i] = 0;
	}

	public function stripWide():Float {
		return width / STRIPS;
	}

	public function stripAt(px:Float):Int {
		final at = Std.int((px - x) / stripWide());
		return at < 0 || at >= STRIPS ? -1 : at;
	}

	public inline function stripLeft(strip:Int):Float {
		return x + Math.round(strip * stripWide());
	}

	public inline function stripRoom(strip:Int):Float {
		return stripLeft(strip + 1) - stripLeft(strip);
	}

	public function metered(much:Float):Void {
		if (Math.abs(much - output) < 0.01) return;

		output = much;
		invalidate();
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

				if (at == MASTER) {
					sliding = at;
					leaned(at, event.y);
					return true;
				}

				final which = at - FIRST;
				final part:Part = which;

				if (metrics != null && event.y > y + height - metrics.row) {
					session.song.muted[which] = !session.song.muted[which];
					session.changed();
					invalidate();
					return true;
				}

				if (onPan(event.y)) {
					session.choose(part);
					turned(which);
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

		if (at == MASTER) {
			if (session.master == want) return;

			session.master = want;
			if (onMaster != null) onMaster(want);

			session.say(translate(mdd.app.Locale.MIXER_MASTER) + " "
				+ Math.round(want * 100 / Song.LOUDEST) + "%");
			session.changed();
			invalidate();
			return;
		}

		final which = at - FIRST;
		if (session.song.volume[which] == want) return;

		session.song.volume[which] = want;
		final part:Part = which;
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
		final small = metrics.small == null ? metrics.body : metrics.small;

		paint.rect(x, y, width, height, theme.panel);

		final head = y + metrics.gap;
		final top = head + panTall() + metrics.unit;
		final tall = height - metrics.gap * 2 - metrics.row - panTall() - metrics.unit;

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final left = stripLeft(FIRST + index);
			final wide = stripRoom(FIRST + index);
			final colour = theme.part(index);
			final quiet = !session.song.audible(part);

			if (session.part.index() == index) {
				paint.rect(left, y, wide, height, theme.accent, Theme.SELECT);
			} else if (index + FIRST == hoverAt) {
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
				metrics.radiusSmall, quiet ? theme.dim : theme.ink,
				index + FIRST == sliding ? 1 : 0.85);

			final level = levels[index];
			final high = tall * (level > 1 ? 1 : level);

			if (high > 1) {
				paint.roundedGradient(middle - track * 0.5, top + tall - high, track, high,
					track * 0.5, colour.lift(0.24), colour.sink(0.2), quiet ? 0.3 : 1);
			}

			if (quiet) {
				paint.roundedRect(left + metrics.unit, y + height - metrics.row + metrics.unit,
					wide - metrics.unit * 2, metrics.row - metrics.unit * 2,
					metrics.radiusSmall, theme.raise1);
			} else {
				paint.roundedGradient(left + metrics.unit,
					y + height - metrics.row + metrics.unit, wide - metrics.unit * 2,
					metrics.row - metrics.unit * 2, metrics.radiusSmall,
					colour.lift(0.22), colour.sink(0.18), 0.35);
			}
		}

		mastered(paint, metrics, theme, stripRoom(MASTER), head, top, tall);

		paint.reface(small);

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final left = stripLeft(FIRST + index);
			final wide = stripRoom(FIRST + index);
			final quiet = !session.song.audible(part);

			paint.textCentred(part.name(), left + wide * 0.5,
				y + height - metrics.row + (metrics.row - small.height) * 0.5 + small.ascent,
				quiet ? theme.dim : theme.ink);

			if (!part.fm()) continue;

			paint.textCentred(sided(session.song.pan[index]), left + wide * 0.5,
				head + (panTall() - small.height) * 0.5 + small.ascent,
				session.song.pan[index] == Song.BOTH ? theme.dim : theme.accent, 0.95);
		}

		paint.textCentred(translate(mdd.app.Locale.MIXER_MASTER),
			stripLeft(MASTER) + stripRoom(MASTER) * 0.5,
			y + height - metrics.row + (metrics.row - small.height) * 0.5 + small.ascent,
			theme.ink);
	}

	function mastered(paint:Paint, metrics:Metrics, theme:Theme, wide:Float, head:Float,
			top:Float, tall:Float):Void {
		final left = stripLeft(MASTER);
		final middle = left + wide * 0.5;
		final track = metrics.whole(10);

		paint.rect(left + wide - metrics.whole(1), y, metrics.whole(1), height, theme.frame, 0.6);

		if (hoverAt == MASTER) {
			paint.rect(left, y, wide, height, theme.accent, Theme.HOVER);
		}

		paint.roundedRect(middle - track * 0.5, top, track, tall, track * 0.5, theme.sink);

		final want = session.master / Song.LOUDEST;
		final knob = metrics.whole(4);
		final at = top + tall * (1 - want);

		paint.roundedRect(middle - track, at - knob * 0.5, track * 2, knob,
			metrics.radiusSmall, theme.ink, sliding == MASTER ? 1 : 0.85);

		final high = tall * (output > 1 ? 1 : output);

		if (high > 1) {
			paint.roundedGradient(middle - track * 0.5, top + tall - high, track, high,
				track * 0.5, theme.accent.lift(0.24), theme.accent.sink(0.2));
		}

		paint.roundedGradient(left + metrics.unit, y + height - metrics.row + metrics.unit,
			wide - metrics.unit * 2, metrics.row - metrics.unit * 2, metrics.radiusSmall,
			theme.accent.lift(0.22), theme.accent.sink(0.18), 0.35);
	}
}
