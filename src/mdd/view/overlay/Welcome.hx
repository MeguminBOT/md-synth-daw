package mdd.view.overlay;

import mdd.app.Languages;
import mdd.app.Locale;
import mdd.app.Session;
import mdd.ui.Input;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Motion;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective
final class Welcome extends Widget {
	public var session:Session;
	public final languages:Array<String> = Languages.shipped();

	public var chosen(default, null):Int = 0;

	public final rise:Motion;
	public final fade:Motion;

	public var onChoose:Null<String -> Void> = null;
	public var onStart:Null<String -> Void> = null;

	var hoverAt:Int = -1;
	var hoverStart:Bool = false;

	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;

		rise = new Motion(this, 0, true);
		fade = new Motion(this, 0, false);
	}

	public function arrive(code:String):Void {
		final root = root();
		if (root == null) return;

		final at = languages.indexOf(code);
		chosen = at < 0 ? 0 : at;

		rise.hold(0);
		fade.hold(0);

		root.start(rise, 1, Motion.ENTER);
		root.start(fade, 1, Motion.ENTER);
	}

	public function code():String {
		return languages.length == 0 ? "en-GB" : languages[chosen];
	}

	override function measure(availableWidth:Float, availableHeight:Float):Void {
		final root = root();
		final metrics = root == null ? null : root.metrics;

		wantWidth = metrics == null ? 420 : metrics.whole(420);
		wantHeight = metrics == null ? 260
			: head() + languages.length * rowTall() + metrics.whole(60);
	}

	public function rowTall():Float {
		final root = root();
		return root == null ? 34 : root.metrics.whole(34);
	}

	function head():Float {
		final root = root();
		return root == null ? 74 : root.metrics.whole(74);
	}

	function buttonTall():Float {
		final root = root();
		return root == null ? 34 : root.metrics.whole(34);
	}

	public function rowAt(py:Float):Int {
		final at = Std.int((py - y - head()) / rowTall());
		return at < 0 || at >= languages.length ? -1 : at;
	}

	public function onButton(px:Float, py:Float):Bool {
		final root = root();
		if (root == null) return false;

		final metrics = root.metrics;
		final tall = buttonTall();
		final top = y + height - metrics.inset - tall;

		return py >= top && py < top + tall
			&& px >= x + width - metrics.inset - metrics.whole(120)
			&& px < x + width - metrics.inset;
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				if (onButton(event.x, event.y)) {
					if (onStart != null) onStart(code());
					return true;
				}

				final at = rowAt(event.y);
				if (at < 0) return true;

				chosen = at;
				if (onChoose != null) onChoose(code());

				invalidate();
				return true;

			case Kind.PointerMove:
				final at = rowAt(event.y);
				final button = onButton(event.x, event.y);

				if (at == hoverAt && button == hoverStart) return true;

				hoverAt = at;
				hoverStart = button;
				invalidate();
				return true;

			case _:
		}

		return true;
	}

	override function hovered(on:Bool):Void {
		if (!on) {
			hoverAt = -1;
			hoverStart = false;
		}
		super.hovered(on);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final alpha = fade.value;

		if (alpha <= 0.004) return;

		final lift = (1 - rise.value) * metrics.sizeOf(8);
		paint.pushTransform(0, lift);

		paint.roundedRect(x, y, width, height, metrics.radiusPanel, theme.raise1, alpha);
		paint.outline(x, y, width, height, theme.frame, metrics.whole(1), alpha);

		final large = metrics.large == null ? metrics.body : metrics.large;
		final font = metrics.body;
		final small = metrics.small == null ? font : metrics.small;

		paint.reface(large);
		paint.text(translate(Locale.APP), x + metrics.inset,
			y + metrics.inset + large.ascent, theme.ink, alpha);

		paint.reface(small);
		paint.text(translate(Locale.WELCOME_LANGUAGE), x + metrics.inset,
			y + metrics.inset + large.height + metrics.gap + small.ascent, theme.dim,
			alpha * 0.85);

		final tall = rowTall();

		for (at in 0...languages.length) {
			final top = y + head() + at * tall;

			if (at == chosen) {
				paint.roundedRect(x + metrics.inset, top, width - metrics.inset * 2, tall - 2,
					metrics.radiusRow, theme.accent, Theme.SELECT);
			} else if (at == hoverAt) {
				paint.roundedRect(x + metrics.inset, top, width - metrics.inset * 2, tall - 2,
					metrics.radiusRow, theme.accent, Theme.HOVER);
			}

			paint.reface(font);
			paint.text(Languages.named(languages[at]), x + metrics.inset * 2,
				top + (tall - font.height) * 0.5 + font.ascent,
				at == chosen ? theme.ink : theme.dim, alpha);

			paint.reface(small);
			paint.textRight(languages[at], x + width - metrics.inset * 2,
				top + (tall - small.height) * 0.5 + small.ascent, theme.dim, alpha * 0.6);
		}

		final button = buttonTall();
		final top = y + height - metrics.inset - button;
		final wide = metrics.whole(120);
		final left = x + width - metrics.inset - wide;

		paint.roundedRect(left, top, wide, button, metrics.radiusRow, theme.accent,
			hoverStart ? 1 : 0.85);

		paint.reface(font);
		paint.textCentred(translate(Locale.WELCOME_START), left + wide * 0.5,
			top + (button - font.height) * 0.5 + font.ascent, theme.ink, alpha);

		paint.popTransform();
	}
}
