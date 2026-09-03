package mdd.view;

import mdd.app.Locale;
import mdd.app.Session;
import mdd.check.Budget;
import mdd.check.Diagnostic;
import mdd.ui.Input;
import mdd.ui.Key;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Scroll;
import mdd.ui.Theme;

@:unreflective
final class Warnings extends Scroll {
	public final session:Session;

	public var budget:Null<Budget> = null;
	public var chosen(default, null):Int = -1;
	public var painted(default, null):Int = 0;

	var hoverAt:Int = -1;

	public function new(session:Session) {
		super();
		this.session = session;
		focusable = true;
	}

	public function rowTall():Float {
		final root = root();
		return root == null ? 30 : root.metrics.whole(30);
	}

	public function found():Int {
		return budget == null ? 0 : budget.found.length;
	}

	public function rowAt(py:Float):Int {
		final at = Std.int((py - y + offsetY) / rowTall());
		return at < 0 || at >= found() ? -1 : at;
	}

	public function fit():Void {
		contentHeight = found() * rowTall();
		invalidate();
	}

	override function took(event:Input):Bool {
		if (super.took(event)) return true;

		switch (event.kind) {
			case Kind.PointerDown:
				final at = rowAt(event.y);
				if (at < 0) return false;

				chosen = at;
				session.reveal(budget.found[at]);
				invalidate();
				return true;

			case Kind.PointerMove:
				final at = rowAt(event.y);
				if (at == hoverAt) return false;

				hoverAt = at;
				invalidate();
				return true;

			case Kind.KeyDown:
				if (event.code != Key.Return || chosen < 0) return false;
				session.reveal(budget.found[chosen]);
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
		final tall = rowTall();

		paint.rect(x, y, width, height, theme.panel);
		painted = 0;

		if (budget == null || budget.found.length == 0) {
			paint.reface(small);
			paint.text(translate(Locale.PANEL_NO_WARNINGS), x + metrics.inset,
				y + metrics.gap + small.ascent, theme.dim, 0.7);
			return;
		}

		paint.pushClip(x, y, width, height);

		var first = Std.int(offsetY / tall);
		if (first < 0) first = 0;

		var last = Std.int((offsetY + height) / tall) + 1;
		if (last > budget.found.length) last = budget.found.length;

		painted = last - first;

		for (at in first...last) {
			final found = budget.found[at];
			final top = y + at * tall - offsetY;

			if (at == chosen) {
				paint.rect(x, top, width, tall, theme.accent, Theme.SELECT);
			} else if (at == hoverAt) {
				paint.rect(x, top, width, tall, theme.accent, Theme.HOVER);
			}

			final colour = found.severity == Diagnostic.FAULT ? theme.over : theme.warn;
			paint.rect(x, top + 2, metrics.whole(3), tall - 4, colour);

			paint.reface(font);

			final line = top + (tall - font.height) * 0.5 + font.ascent;
			paint.text(found.part.name(), x + metrics.inset, line, theme.part(found.part.index()));

			paint.text(found.saying, x + metrics.inset + metrics.whole(52), line, theme.ink);

			paint.reface(small);
			paint.textRight(found.reason, x + width - metrics.inset,
				top + (tall - small.height) * 0.5 + small.ascent, theme.dim, 0.75);
		}

		paint.popClip();
		bar(paint);
	}
}
