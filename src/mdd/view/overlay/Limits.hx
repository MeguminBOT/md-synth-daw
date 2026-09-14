package mdd.view.overlay;

import mdd.app.Locale;
import mdd.ui.Font;
import mdd.ui.Input;
import mdd.ui.Key;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Motion;
import mdd.ui.Paint;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective

/**
	The console limits sheet, raised from the help menu: each limit the Mega Drive puts on its
	music, and how the music written for it worked around that limit.
**/
final class Limits extends Widget {
	static final TITLES:Array<Int> = [Locale.LIMITS_FM_TITLE, Locale.LIMITS_LFO_TITLE,
		Locale.LIMITS_PAN_TITLE, Locale.LIMITS_LEVEL_TITLE, Locale.LIMITS_SQUARE_TITLE,
		Locale.LIMITS_THREE_TITLE, Locale.LIMITS_SAMPLE_TITLE, Locale.LIMITS_CHORD_TITLE,
		Locale.LIMITS_RELEASE_TITLE];

	static final BODIES:Array<Int> = [Locale.LIMITS_FM_BODY, Locale.LIMITS_LFO_BODY,
		Locale.LIMITS_PAN_BODY, Locale.LIMITS_LEVEL_BODY, Locale.LIMITS_SQUARE_BODY,
		Locale.LIMITS_THREE_BODY, Locale.LIMITS_SAMPLE_BODY, Locale.LIMITS_CHORD_BODY,
		Locale.LIMITS_RELEASE_BODY];

	static final FIXES:Array<Int> = [Locale.LIMITS_FM_FIX, Locale.LIMITS_LFO_FIX,
		Locale.LIMITS_PAN_FIX, Locale.LIMITS_LEVEL_FIX, Locale.LIMITS_SQUARE_FIX,
		Locale.LIMITS_THREE_FIX, Locale.LIMITS_SAMPLE_FIX, Locale.LIMITS_CHORD_FIX,
		Locale.LIMITS_RELEASE_FIX];

	static inline final HEADING = 0;
	static inline final BODY = 1;
	static inline final LABEL = 2;
	static inline final FIX = 3;
	static inline final GAP = 4;

	/**
		Called when it closes.
	**/
	public var onShut:Null<Void -> Void> = null;

	/**
		How far it has risen into place.
	**/
	public final rise:Motion;

	/**
		How far it has faded in.
	**/
	public final fade:Motion;

	/**
		How far the text is scrolled down.
	**/
	public var scrolled(default, null):Float = 0;

	final lines:Array<String> = [];
	final kinds:Array<Int> = [];

	var linesFor:String = "";
	var linesWide:Float = -1;
	var linesFace:Null<Font> = null;
	var reach:Float = 0;

	/**
		Builds the sheet.
	**/
	public function new() {
		super();
		modal = true;

		opaque = true;
		focusable = true;

		rise = new Motion(this, 0, true);
		fade = new Motion(this, 0, false);
	}

	/**
		Starts the fade and the rise, from the top of the text.
	**/
	public function arrive():Void {
		scrolled = 0;

		final root = root();
		if (root == null) return;

		rise.hold(0);
		fade.hold(0);

		root.start(rise, 1, Motion.ENTER);
		root.start(fade, 1, Motion.ENTER);
	}

	/**
		@return How tall the title band is.
	**/
	public function head():Float {
		final root = root();
		return root == null ? 50 : root.metrics.whole(50);
	}

	/**
		@return How much room the text has.
	**/
	public function room():Float {
		final root = root();
		return height - head() - (root == null ? 16 : root.metrics.inset);
	}

	/**
		@return How tall the text is once broken into lines, nought until the sheet has been
			drawn once.
	**/
	public function content():Float {
		return reach;
	}

	/**
		Scrolls the text, clamped to it.

		@param py How far down.
	**/
	public function scrollTo(py:Float):Void {
		final most = reach - room();

		scrolled = py < 0 ? 0 : (py > most ? (most < 0 ? 0 : most) : py);
		invalidate();
	}

	function step():Float {
		final root = root();
		return root == null ? 40 : root.metrics.whole(40);
	}

	function indent(metrics:Metrics):Float {
		return metrics.gap * 2;
	}

	function tallOf(kind:Int, metrics:Metrics, body:Font, small:Font):Float {
		return switch (kind) {
			case HEADING: body.height + metrics.gap * 0.5;
			case GAP: metrics.gap * 2;
			case _: small.height;
		}
	}

	/**
		Breaks the text into lines for the width it is drawn at, once, because it changes only
		when the language, the width or the face does, and it is wanted on every frame.

		@param metrics What to measure in.
	**/
	function words(metrics:Metrics):Void {
		final root = root();
		final body = metrics.body;
		final small = metrics.small == null ? metrics.body : metrics.small;

		if (root == null || body == null || small == null) return;

		final room = width - metrics.inset * 2 - metrics.gap;
		final spoken = root.translation.language;

		if (spoken == linesFor && room == linesWide && small == linesFace) return;

		linesFor = spoken;
		linesWide = room;
		linesFace = small;

		lines.resize(0);
		kinds.resize(0);

		adds(small.wrapped(translate(Locale.LIMITS_INTRO), room), BODY);

		for (index in 0...TITLES.length) {
			lines.push("");
			kinds.push(GAP);

			adds(body.wrapped(translate(TITLES[index]), room), HEADING);
			adds(small.wrapped(translate(BODIES[index]), room), BODY);
			adds(small.wrapped(translate(Locale.LIMITS_WORKAROUND), room - indent(metrics)),
				LABEL);
			adds(small.wrapped(translate(FIXES[index]), room - indent(metrics)), FIX);
		}

		reach = 0;
		for (kind in kinds) reach += tallOf(kind, metrics, body, small);

		scrollTo(scrolled);
	}

	function adds(said:Array<String>, kind:Int):Void {
		for (line in said) {
			lines.push(line);
			kinds.push(kind);
		}
	}

	override function measure(availableWidth:Float, availableHeight:Float):Void {
		final root = root();
		final metrics = root == null ? null : root.metrics;

		final wide = metrics == null ? 600 : metrics.whole(600);
		final tall = metrics == null ? 680 : metrics.whole(680);

		wantWidth = wide < availableWidth * 0.94 ? wide : availableWidth * 0.94;
		wantHeight = tall < availableHeight * 0.9 ? tall : availableHeight * 0.9;
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.Wheel:
				scrollTo(scrolled - event.dy * step());

			case Kind.KeyDown:
				if (event.code == Key.Escape) {
					if (onShut != null) onShut();
				} else if (event.code == Key.Down) {
					scrollTo(scrolled + step());
				} else if (event.code == Key.Up) {
					scrollTo(scrolled - step());
				} else if (event.code == Key.PageDown) {
					scrollTo(scrolled + room() * 0.9);
				} else if (event.code == Key.PageUp) {
					scrollTo(scrolled - room() * 0.9);
				} else if (event.code == Key.Home) {
					scrollTo(0);
				} else if (event.code == Key.End) {
					scrollTo(reach);
				}

			case Kind.PointerDown:
				final outside = event.x < x || event.x > x + width || event.y < y
					|| event.y > y + height;

				if (outside && onShut != null) onShut();

			case _:
		}

		return true;
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final alpha = fade.value;

		if (alpha <= 0.004) return;

		words(metrics);

		final lift = (1 - rise.value) * metrics.sizeOf(8);
		paint.pushTransform(0, lift);

		paint.roundedRect(x, y, width, height, metrics.radiusPanel, theme.raise1, alpha);
		paint.outline(x, y, width, height, theme.frame, metrics.whole(1), alpha,
			metrics.radiusPanel);

		final font = metrics.large == null ? metrics.body : metrics.large;
		final body = metrics.body;
		final small = metrics.small == null ? metrics.body : metrics.small;

		paint.reface(font);
		paint.text(translate(Locale.HELP_LIMITS), x + metrics.inset,
			y + metrics.inset + font.ascent, theme.ink, alpha);

		paint.reface(small);
		paint.textRight(translate(Locale.PREFERENCES_CLOSE), x + width - metrics.inset,
			y + metrics.inset + small.ascent, theme.dim, alpha * 0.7);

		final top = y + head();
		final bottom = top + room();
		final rule = metrics.whole(2);

		paint.pushClip(x, top, width, room());

		var at = top - scrolled;

		for (index in 0...lines.length) {
			final kind = kinds[index];
			final tall = tallOf(kind, metrics, body, small);

			if (kind != GAP && at + tall >= top && at <= bottom) {
				final face = kind == HEADING ? body : small;
				final aside = kind == LABEL || kind == FIX;
				final left = x + metrics.inset + (aside ? indent(metrics) : 0);

				if (aside) paint.rect(x + metrics.inset, at, rule, tall, theme.accent, alpha * 0.6);

				paint.reface(face);
				paint.text(lines[index], left, at + face.ascent,
					kind == LABEL ? theme.accent : theme.ink,
					kind == BODY || kind == FIX ? alpha * 0.85 : alpha);
			}

			at += tall;
		}

		paint.popClip();

		reined(paint, theme, metrics, alpha);
		paint.popTransform();
	}

	function reined(paint:Paint, theme:Theme, metrics:Metrics, alpha:Float):Void {
		final tall = room();

		if (reach <= tall + 0.5) return;

		final thick = metrics.whole(4);
		final held = tall * tall / reach;
		final least = metrics.whole(24);
		final span = held < least ? least : held;
		final at = scrolled / (reach - tall) * (tall - span);

		paint.roundedRect(x + width - metrics.gap - thick, y + head() + at, thick, span,
			thick * 0.5, theme.frame, alpha * 0.9);
	}
}
