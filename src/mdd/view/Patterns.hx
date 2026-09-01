package mdd.view;

import mdd.song.Pattern;
import mdd.song.Part;
import mdd.song.Tempo;
import mdd.song.edit.AddPattern;
import mdd.ui.Input;
import mdd.ui.Key;
import mdd.ui.Kind;
import mdd.ui.Paint;
import mdd.ui.Scroll;
import mdd.ui.Theme;

@:unreflective
final class Patterns extends Scroll {
	public final session:Session;

	public var painted(default, null):Int = 0;

	var hoverAt:Int = -1;

	public function new(session:Session) {
		super();
		this.session = session;
		focusable = true;
	}

	public function rowTall():Float {
		final root = root();
		return root == null ? 26 : root.metrics.whole(26);
	}

	public function rowAt(py:Float):Int {
		final at = Std.int((py - y + offsetY) / rowTall());
		return at < 0 || at >= session.song.patterns.length ? -1 : at;
	}

	public function choose(index:Int):Void {
		if (index < 0 || index >= session.song.patterns.length) return;
		if (session.pattern == index) return;

		session.pattern = index;
		session.changed();
	}

	public function added():Void {
		final held = session.current();
		final length = held == null ? Tempo.TICKS * 4 : held.length;

		session.does(new AddPattern(new Pattern(named(), length)));
		session.pattern = session.song.patterns.length - 1;
		session.changed();
	}

	function named():String {
		return translate(Locale.PATTERN) + " " + (session.song.patterns.length + 1);
	}

	override function took(event:Input):Bool {
		if (super.took(event)) return true;

		switch (event.kind) {
			case Kind.PointerDown:
				final at = rowAt(event.y);
				if (at < 0) return false;

				choose(at);
				return true;

			case Kind.PointerMove:
				final at = rowAt(event.y);
				if (at == hoverAt) return false;

				hoverAt = at;
				invalidate();
				return true;

			case Kind.KeyDown:
				if (event.code == Key.Down) {
					choose(session.pattern + 1);
					return true;
				}

				if (event.code == Key.Up) {
					choose(session.pattern - 1);
					return true;
				}

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
		final tall = rowTall();

		contentHeight = session.song.patterns.length * tall;

		paint.rect(x, y, width, height, theme.panel);
		paint.pushClip(x, y, width, height);
		paint.reface(font);

		var first = Std.int(offsetY / tall);
		if (first < 0) first = 0;

		var last = Std.int((offsetY + height) / tall) + 1;
		if (last > session.song.patterns.length) last = session.song.patterns.length;

		painted = last - first;

		for (at in first...last) {
			final held = session.song.patterns[at];
			final top = y + at * tall - offsetY;
			final line = top + (tall - font.height) * 0.5 + font.ascent;

			if (at == session.pattern) paint.rect(x, top, width, tall, theme.accent, Theme.SELECT);
			else if (at == hoverAt) paint.rect(x, top, width, tall, theme.accent, Theme.HOVER);

			paint.rect(x, top + 2, metrics.whole(3), tall - 4, colour(held, at));
			paint.text(held.name, x + metrics.inset, line, theme.ink);

			paint.reface(small);
			paint.textRight(bars(held) + "   " + held.notes(), x + width - metrics.inset,
				line, theme.dim, 0.75);
			paint.reface(font);
		}

		paint.popClip();
	}

	function colour(held:Pattern, at:Int):Int {
		if (held.colour >= 0) return held.colour;
		return Theme.PARTS[at % Theme.PARTS.length];
	}

	function bars(held:Pattern):String {
		final beats = held.length / Tempo.TICKS;
		final whole = Math.round(beats / 4 * 100) / 100;

		return whole + " " + translate(whole == 1 ? Locale.PATTERN_BAR : Locale.PATTERN_BARS);
	}
}
