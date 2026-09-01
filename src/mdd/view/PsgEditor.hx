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

	public final session:Session;

	public var held(default, null):Int = -1;

	var grabbing:Bool = false;

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
		return root == null ? 40 : root.metrics.whole(40);
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
				grabbing = true;
				drew(envelope, event);
				return true;

			case Kind.PointerMove:
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
				if (!grabbing) return false;

				grabbing = false;
				session.changed();
				return true;

			case _:
		}

		return false;
	}

	function drew(envelope:Envelope, event:Input):Void {
		final at = stepAt(event.x);
		if (at < 0) return;

		final top = y + head();
		final tall = height - head() - (root() == null ? 8 : root().metrics.gap);

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

		if (envelope == null) {
			paint.text(session.part.name() + " is not a square or the noise",
				x + metrics.inset, y + metrics.gap + small.ascent, theme.dim);
			return;
		}

		paint.text(session.part.name() + "   attenuation over time, loudest at the top",
			x + metrics.inset, y + metrics.gap + small.ascent, theme.dim);

		if (session.part.noise()) {
			paint.text("noise mode " + envelope.noise, x + metrics.inset,
				y + metrics.gap + small.height + small.ascent, theme.dim, 0.8);
		}

		final top = y + head();
		final tall = height - head() - metrics.gap;
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
	}
}
