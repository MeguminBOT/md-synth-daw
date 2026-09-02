package mdd.view;

import mdd.ui.Flow;
import mdd.ui.Input;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Motion;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective
final class Preferences extends Widget {
	public static inline final THEME = 0;
	public static inline final TYPEFACE = 1;
	public static inline final MOTION = 2;
	public static inline final LANGUAGE = 3;
	public static inline final DENSITY = 4;
	public static inline final KEEPING = 5;
	public static inline final ROWS = 6;

	static final NAMES:Array<String> = [Locale.PREFERENCE_THEME, Locale.PREFERENCE_TYPEFACE,
		Locale.PREFERENCE_MOTION, Locale.PREFERENCE_LANGUAGE, Locale.PREFERENCE_DENSITY,
		Locale.PREFERENCE_KEEPING];

	static final KEEPINGS:Array<String> = [Locale.KEEPING_NEVER, Locale.KEEPING_ONE,
		Locale.KEEPING_FIVE, Locale.KEEPING_TEN];

	public static final MINUTES:Array<Float> = [0, 60, 300, 600];

	static final THEMES:Array<String> = [Locale.THEME_MIDNIGHT, Locale.THEME_RACK,
		Locale.THEME_SLATE];
	static final MOTIONS:Array<String> = [Locale.MOTION_FULL, Locale.MOTION_REDUCED,
		Locale.MOTION_NONE];
	static final TYPEFACES:Array<String> = [Locale.TYPEFACE_GO, Locale.TYPEFACE_PLEX,
		Locale.TYPEFACE_INTER, Locale.TYPEFACE_BARLOW];
	static final DENSITIES:Array<String> = [Locale.DENSITY_CLOSE, Locale.DENSITY_USUAL,
		Locale.DENSITY_ROOMY];

	public final session:Session;
	public final languages:Array<String> = [];
	public final spoken:Array<String> = [];

	public var chosen(default, null):Int = 0;
	public var density(default, null):Int = 1;
	public var language(default, null):Int = 0;
	public var keeping(default, null):Int = 2;

	public final rise:Motion;
	public final fade:Motion;

	public var onScale:Null<Float -> Void> = null;
	public var onTypeface:Null<Int -> Void> = null;
	public var onKeep:Null<Void -> Void> = null;
	public var onKeeping:Null<Float -> Void> = null;

	var hoverAt:Int = -1;
	var hoverOn:Int = -1;

	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;

		rise = new Motion(this, 0, true);
		fade = new Motion(this, 0, false);
	}

	public var onSpeak:Null<String -> Void> = null;

	public function speaks(codes:Array<String>, code:String):Void {
		languages.resize(0);
		spoken.resize(0);

		for (held in codes) {
			languages.push(Languages.named(held));
			spoken.push(held);
		}

		final at = spoken.indexOf(code);
		language = at < 0 ? 0 : at;

		invalidate();
	}

	public function arrive():Void {
		final root = root();
		if (root == null) return;

		rise.hold(0);
		fade.hold(0);

		root.start(rise, 1, Motion.ENTER);
		root.start(fade, 1, Motion.ENTER);
	}

	override function measure(availableWidth:Float, availableHeight:Float):Void {
		final root = root();
		final metrics = root == null ? null : root.metrics;

		wantWidth = metrics == null ? 560 : metrics.whole(560);
		wantHeight = metrics == null ? 300 : head() + ROWS * rowTall() + metrics.inset;
	}

	public function rowTall():Float {
		final root = root();
		return root == null ? 44 : root.metrics.whole(44);
	}

	public function head():Float {
		final root = root();
		return root == null ? 46 : root.metrics.whole(46);
	}

	public function showing(row:Int):Int {
		return holding(row);
	}

	public function rowAt(py:Float):Int {
		final at = Std.int((py - y - head()) / rowTall());
		return at < 0 || at >= ROWS ? -1 : at;
	}

	public function choices(row:Int):Array<String> {
		return switch (row) {
			case THEME: THEMES;
			case TYPEFACE: TYPEFACES;
			case MOTION: MOTIONS;
			case DENSITY: DENSITIES;
			case KEEPING: KEEPINGS;
			case _: languages;
		}
	}

	public function holding(row:Int):Int {
		return switch (row) {
			case THEME: session.theme;
			case TYPEFACE: session.typeface;
			case MOTION: session.motion;
			case DENSITY: density;
			case KEEPING: keeping;
			case _: language;
		}
	}

	public function chose(row:Int, which:Int):Void {
		final root = root();

		switch (row) {
			case THEME:
				session.theme = which;
				if (root != null) root.theme.wear(which);
				session.say("theme " + which);

			case TYPEFACE:
				session.typeface = which;
				if (onTypeface != null) onTypeface(which);

			case MOTION:
				session.motion = which;
				if (root != null) root.flow = which;
				session.say("motion " + which);

			case DENSITY:
				density = which;
				if (onScale != null) onScale(1.0 + which * 0.15);

			case KEEPING:
				keeping = which;
				if (onKeeping != null) onKeeping(MINUTES[which]);
				session.say(which == 0 ? "no saving on its own"
					: "saving on its own every " + Std.int(MINUTES[which] / 60) + " minutes");

			case _:
				language = which;

				if (which < spoken.length && onSpeak != null) onSpeak(spoken[which]);
				session.say(which < languages.length ? languages[which] : "");
		}

		if (root != null) root.reshape();

		session.changed();
		invalidate();

		if (onKeep != null) onKeep();
	}

	public function optionAt(row:Int, px:Float):Int {
		final root = root();
		if (root == null) return -1;

		final held = choices(row);
		final metrics = root.metrics;
		final wide = (width - metrics.inset * 2) / held.length;

		final at = Std.int((px - x - metrics.inset) / wide);
		return at < 0 || at >= held.length ? -1 : at;
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				final row = rowAt(event.y);
				if (row < 0) return true;

				final which = optionAt(row, event.x);
				if (which < 0) return true;

				chose(row, which);
				return true;

			case Kind.PointerMove:
				final row = rowAt(event.y);
				final which = row < 0 ? -1 : optionAt(row, event.x);

				if (row == hoverAt && which == hoverOn) return true;

				hoverAt = row;
				hoverOn = which;
				invalidate();
				return true;

			case _:
		}

		return true;
	}

	override function hovered(on:Bool):Void {
		if (!on) {
			hoverAt = -1;
			hoverOn = -1;
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

		final font = metrics.body;
		final small = metrics.small == null ? font : metrics.small;

		paint.reface(font);
		paint.text(translate(Locale.PREFERENCES), x + metrics.inset,
			y + metrics.inset + font.ascent, theme.ink, alpha);

		paint.reface(small);
		paint.textRight(translate(Locale.PREFERENCES_CLOSE), x + width - metrics.inset,
			y + metrics.inset + small.ascent, theme.dim, alpha * 0.8);

		final tall = rowTall();

		for (row in 0...ROWS) {
			final top = y + head() + row * tall;

			paint.reface(small);
			paint.text(translate(NAMES[row]), x + metrics.inset, top + small.ascent,
				theme.dim, alpha * 0.9);

			final held = choices(row);
			final wide = (width - metrics.inset * 2) / held.length;
			final on = holding(row);
			final button = tall - small.height - metrics.gap;

			for (which in 0...held.length) {
				final left = x + metrics.inset + which * wide;
				final at = top + small.height + metrics.unit;

				paint.roundedRect(left + 1, at, wide - 2, button - metrics.unit,
					metrics.radiusSmall,
					which == on ? theme.accent : theme.raise2,
					which == on ? 0.85 : 1);

				if (row == hoverAt && which == hoverOn && which != on) {
					paint.roundedRect(left + 1, at, wide - 2, button - metrics.unit,
						metrics.radiusSmall, theme.accent, Theme.HOVER);
				}

				final label = row == LANGUAGE ? held[which] : translate(held[which]);

				paint.pushClip(left + 1, at, wide - 2, button - metrics.unit);
				paint.textCentred(label, left + wide * 0.5,
					at + (button - metrics.unit - small.height) * 0.5 + small.ascent,
					which == on ? theme.ink : theme.dim, alpha);
				paint.popClip();
			}
		}

		paint.popTransform();
	}
}
