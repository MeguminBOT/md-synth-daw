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
	public var automating(default, null):Int = Session.LANES;

	static inline final WAYS = 2;

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
		wantHeight = metrics == null ? 380
			: head() + languages.length * rowTall() + asking() + WAYS * wayTall()
			+ metrics.whole(60);
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

	function wayTall():Float {
		final root = root();
		return root == null ? 48 : root.metrics.whole(48);
	}

	function asking():Float {
		final root = root();
		return root == null ? 34 : root.metrics.whole(34);
	}

	function waysTop():Float {
		return y + head() + languages.length * rowTall() + asking();
	}

	function wayAt(py:Float):Int {
		final at = Std.int((py - waysTop()) / wayTall());
		return at < 0 || at >= WAYS ? -1 : at;
	}

	public function picks(which:Int):Void {
		if (which < 0 || which >= WAYS) return;

		automating = which;
		session.automating = which;

		invalidate();
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

				final way = wayAt(event.y);

				if (way >= 0) {
					picks(way);
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

	static final WAYS_SAID:Array<Locale> = [Locale.AUTOMATING_LANES, Locale.AUTOMATING_CLIPS];

	function ways(paint:Paint, theme:Theme, metrics:Metrics, alpha:Float):Void {
		final font = metrics.body;
		final small = metrics.small == null ? font : metrics.small;
		final tall = wayTall();
		final top = waysTop();

		paint.reface(small);
		paint.text(translate(Locale.AUTOMATING_ASK), x + metrics.inset,
			top - metrics.gap - small.descent, theme.dim, alpha * 0.85);

		for (way in 0...WAYS) {
			final row = top + way * tall;
			final picked = way == automating;

			if (picked) {
				paint.roundedRect(x + metrics.inset, row, width - metrics.inset * 2,
					tall - 2, metrics.radiusRow, theme.accent, Theme.SELECT);
			}

			paint.outline(x + metrics.inset, row, width - metrics.inset * 2, tall - 2,
				picked ? theme.accent : theme.frame, metrics.whole(1), alpha,
				metrics.radiusRow);

			final art = x + width - metrics.inset - metrics.whole(56);
			final middle = row + (tall - 2) * 0.5;
			final ink = picked ? theme.accent : theme.dim;

			if (way == Session.LANES) {
				for (line in 0...3) {
					final at = row + (tall - 2) * (line + 1) / 4;
					paint.rect(art, at - metrics.whole(1), metrics.whole(44),
						metrics.whole(2), ink, alpha * (line == 1 ? 0.9 : 0.45));
				}
			} else {
				final deep = metrics.whole(20);
				final wide = metrics.whole(44);

				paint.outline(art, middle - deep * 0.5, wide, deep, ink, metrics.whole(1),
					alpha * 0.6);

				final low = middle + deep * 0.25;
				final high = middle - deep * 0.25;
				final step = wide / 3;

				paint.line(art + metrics.whole(3), low, art + step, low, metrics.whole(2),
					ink, alpha * 0.9);
				paint.line(art + step, low, art + step * 2, high, metrics.whole(2), ink,
					alpha * 0.9);
				paint.line(art + step * 2, high, art + wide - metrics.whole(3), high,
					metrics.whole(2), ink, alpha * 0.9);
			}

			paint.reface(font);
			paint.text(translate(WAYS_SAID[way]), x + metrics.inset * 2,
				row + (tall - 2 - font.height) * 0.5 + font.ascent,
				picked ? theme.ink : theme.dim, alpha);
		}
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
		paint.outline(x, y, width, height, theme.frame, metrics.whole(1), alpha,
			metrics.radiusPanel);

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

			paint.outline(x + metrics.inset, top, width - metrics.inset * 2, tall - 2,
				at == chosen ? theme.accent : theme.frame, metrics.whole(1), alpha,
				metrics.radiusRow);

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

		paint.roundedGradient(left, top, wide, button, metrics.radiusRow,
			theme.accent.lift(0.20), theme.accent.sink(0.16), hoverStart ? 1 : 0.85);

		paint.reface(font);
		paint.textCentred(translate(Locale.WELCOME_START), left + wide * 0.5,
			top + (button - font.height) * 0.5 + font.ascent, theme.ink, alpha);

		ways(paint, theme, metrics, alpha);

		paint.popTransform();
	}
}
