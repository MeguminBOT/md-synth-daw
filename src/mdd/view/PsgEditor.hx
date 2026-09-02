package mdd.view;

import mdd.song.Envelope;
import mdd.song.Instrument;
import mdd.ui.Input;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective
final class PsgEditor extends Widget {
	public static inline final STEPS = 32;

	public static inline final LOOP = 0;
	public static inline final SPEED = 1;
	public static inline final NOISE = 2;
	public static inline final DIALS = 3;

	static final DIAL_NAMES:Array<String> = ["LOOP", "SPEED", "NOISE"];

	public final session:Session;

	public var held(default, null):Int = -1;
	public var dial(default, null):Int = -1;

	var grabbing:Bool = false;
	var turning:Int = -1;
	var grabAt:Float = 0;
	var grabWas:Int = 0;

	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;
	}

	public function envelope():Null<Envelope> {
		if (!session.part.square() && !session.part.noise()) return null;

		final instrument = session.song.instrumentAt(session.song.rack[session.part.index()]);
		return instrument == null ? null : instrument.envelope;
	}

	function head():Float {
		final root = root();
		return root == null ? 62 : root.metrics.whole(62);
	}

	function dialTall():Float {
		final root = root();
		return root == null ? 22 : root.metrics.whole(22);
	}

	function dialsTop():Float {
		return y + head() - dialTall() - (root() == null ? 4.0 : root().metrics.unit);
	}

	function dialCount():Int {
		return session.part.noise() ? DIALS : DIALS - 1;
	}

	public function dialAt(px:Float, py:Float):Int {
		final root = root();
		if (root == null) return -1;

		final top = dialsTop();
		final tall = dialTall();

		if (py < top || py >= top + tall) return -1;

		final inset = root.metrics.inset;
		final wide = (width - inset * 2) / dialCount();
		final at = Std.int((px - x - inset) / wide);

		return at < 0 || at >= dialCount() ? -1 : at;
	}

	public function dialOf(envelope:Envelope, which:Int):Int {
		return switch (which) {
			case LOOP: envelope.loop;
			case SPEED: envelope.speed;
			case _: envelope.noise;
		}
	}

	public function turnTo(envelope:Envelope, which:Int, value:Int):Void {
		switch (which) {
			case LOOP:
				envelope.loop = value < -1 ? -1 : (value >= STEPS ? STEPS - 1 : value);

			case SPEED:
				envelope.speed = value < 1 ? 1 : (value > 16 ? 16 : value);

			case _:
				envelope.noise = value < 0 ? 0 : (value > 7 ? 7 : value);
		}
	}

	public function dialSpan(which:Int):Float {
		return switch (which) {
			case LOOP: STEPS - 1;
			case SPEED: 16;
			case _: 7;
		}
	}

	function stepWide():Float {
		return width / STEPS;
	}

	public function stepAt(px:Float):Int {
		final at = Std.int((px - x) / stepWide());
		return at < 0 || at >= STEPS ? -1 : at;
	}

	public function levelAt(py:Float, top:Float, tall:Float):Int {
		final part = (py - top) / tall;
		final level = Math.round(part * 15);

		return level < 0 ? 0 : (level > 15 ? 15 : level);
	}

	override function took(event:Input):Bool {
		final envelope = envelope();
		if (envelope == null) return false;

		switch (event.kind) {
			case Kind.PointerDown:
				final turned = dialAt(event.x, event.y);

				if (turned >= 0) {
					turning = turned;
					grabAt = event.x;
					grabWas = dialOf(envelope, turned);
					dial = turned;
					invalidate();
					return true;
				}

				if (event.y < dialsTop()) return false;

				grabbing = true;
				drew(envelope, event);
				return true;

			case Kind.PointerMove:
				if (turning >= 0) {
					turnTo(envelope, turning,
						grabWas + Std.int((event.x - grabAt) / (event.ctrl() ? 24 : 8)));
					invalidate();
					return true;
				}

				if (!grabbing) {
					final at = stepAt(event.x);
					if (at == held) return false;

					held = at;
					invalidate();
					return true;
				}

				drew(envelope, event);
				return true;

			case Kind.PointerUp:
				if (turning >= 0) {
					turning = -1;
					session.changed();
					return true;
				}

				if (!grabbing) return false;

				grabbing = false;
				session.changed();
				return true;

			case Kind.Wheel:
				final turned = dialAt(event.x, event.y);
				if (turned < 0) return false;

				turnTo(envelope, turned, dialOf(envelope, turned) + Std.int(event.dy));
				session.changed();
				invalidate();
				return true;

			case _:
		}

		return false;
	}

	public function graphTall():Float {
		final root = root();
		if (root == null) return 220;

		final room = height - head() - root.metrics.gap;
		final most = root.metrics.whole(240);

		return room > most ? most : room;
	}

	function drew(envelope:Envelope, event:Input):Void {
		final at = stepAt(event.x);
		if (at < 0) return;

		final top = y + head();
		final tall = graphTall();

		while (envelope.steps.length <= at) envelope.steps.push(0);
		envelope.steps[at] = levelAt(event.y, top, tall);

		held = at;
		invalidate();
	}

	override function hovered(on:Bool):Void {
		if (!on) held = -1;
		super.hovered(on);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final envelope = envelope();

		paint.rect(x, y, width, height, theme.panel);

		final small = metrics.small == null ? metrics.body : metrics.small;
		paint.reface(small);

		Panel.titled(paint, theme, metrics, session.part.name() + "   "
			+ translate(envelope == null ? Locale.PANEL_NOT_SQUARE : Locale.PANEL_ENVELOPE),
			x, y, width, metrics.whole(22));

		paint.reface(small);

		if (envelope == null) return;

		dials(paint, theme, metrics, envelope);

		final top = y + head();
		final tall = graphTall();
		final wide = stepWide();
		final colour = theme.part(session.part.index());

		paint.rect(x, top, width, tall, theme.sink, 0.5);

		for (level in 0...4) {
			final at = top + tall * level / 4;
			paint.rect(x, at, width, metrics.whole(1), theme.frame, 0.3);
		}

		for (step in 0...STEPS) {
			final value = envelope.at(step);
			final quiet = value >= 15;
			final left = x + step * wide;

			if (step == envelope.loop) {
				paint.rect(left, top, metrics.whole(1), tall, theme.accent, 0.8);
			}

			if (step == held) paint.rect(left, top, wide, tall, theme.accent, Theme.HOVER);

			if (quiet) continue;

			final high = tall * (15 - value) / 15;
			paint.roundedRect(left + 1, top + tall - high, wide - 2, high, metrics.radiusSmall,
				colour, step < envelope.steps.length ? 0.9 : 0.35);
		}

		paint.rect(x, top + tall, width, metrics.whole(1), theme.frame);

		paint.reface(small);
		paint.text(translate(Locale.PSG_STEPS) + " " + envelope.steps.length,
			x + metrics.inset, top + tall + metrics.gap + small.ascent, theme.dim, 0.8);
	}

	function dials(paint:Paint, theme:Theme, metrics:Metrics, envelope:Envelope):Void {
		final font = metrics.small == null ? metrics.body : metrics.small;
		final top = dialsTop();
		final tall = dialTall();
		final many = dialCount();
		final room = (width - metrics.inset * 2) / many;
		final colour = theme.part(session.part.index());

		paint.reface(font);

		for (which in 0...many) {
			final left = x + metrics.inset + which * room;
			final wide = room - metrics.unit;
			final value = dialOf(envelope, which);
			final span = dialSpan(which);
			final part = span <= 0 ? 0.0 : (value < 0 ? 0.0 : value / span);

			paint.roundedRect(left, top, wide, tall, metrics.radiusSmall, theme.raise1);

			if (part > 0) {
				paint.roundedRect(left, top, wide * part, tall, metrics.radiusSmall, colour,
					0.45);
			}

			paint.outline(left, top, wide, tall, which == dial ? theme.accent : theme.frame,
				metrics.whole(1));

			final line = top + (tall - font.height) * 0.5 + font.ascent;
			final said = which == LOOP && value < 0 ? translate(Locale.PSG_NO_LOOP)
				: Std.string(value);

			paint.text(DIAL_NAMES[which], left + metrics.unit, line, theme.dim, 0.85);
			paint.textRight(said, left + wide - metrics.unit, line, theme.ink);
		}
	}
}
