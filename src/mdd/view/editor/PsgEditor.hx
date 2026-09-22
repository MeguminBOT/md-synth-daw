package mdd.view.editor;

import mdd.app.Locale;
import mdd.app.Session;
import mdd.song.Envelope;
import mdd.song.Instrument;
import mdd.ui.Input;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Panel;
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective

/**
	The square editor: an envelope drawn as steps, and the three dials that decide how
	it runs.

	The FM part has envelopes in hardware and the squares do not, so an envelope here
	is the list of attenuation writes a driver would make on a frame timer.
**/
final class PsgEditor extends Widget {
	/**
		How many steps an envelope may have, which the model owns.
	**/
	public static inline final STEPS = Envelope.LENGTH;

	/**
		Dial: which step to return to, or none to stop at the end.
	**/
	public static inline final LOOP = Envelope.LOOP;
	static inline final SPEED = Envelope.SPEED;

	/**
		Dial: the noise control nibble, for an envelope on the noise channel.
	**/
	public static inline final NOISE = Envelope.NOISE;

	/**
		How many dials there are.
	**/
	public static inline final DIALS = Envelope.DIALS;

	/**
		What each dial of the envelope is called. These are words rather than what the
		documentation calls a register, so they are looked up.
	**/
	static final DIAL_NAMES:Array<Locale> = [Locale.FIELD_LOOP, Locale.FIELD_SPEED,
		Locale.FIELD_NOISE];

	/**
		The session to read.
	**/
	public final session:Session;

	/**
		Which step the pointer is over, or -1.
	**/
	public var held(default, null):Int = -1;

	/**
		Which dial the pointer is over, or -1.
	**/
	public var dial(default, null):Int = -1;

	/**
		How far the pointer moves for one step with the precision key held.
	**/
	static inline final FINE = 4.0;

	var grabbing:Bool = false;
	var fining:Bool = false;
	var fineX:Float = 0;
	var fineWas:Int = 0;
	var turning:Int = -1;
	var grabWas:Int = 0;

	final wereSteps:Array<Int> = [];

	/**
		Builds the editor.

		@param session The session to read.
	**/
	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;
	}

	/**
		@return The envelope of the chosen part, or null where it has none.
	**/
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

	/**
		@param px A point, across.
		@param py A point, down.
		@return Which dial is there, or -1.
	**/
	/**
		@return The preset this channel was loaded from, or null where it came from none or where
			that preset is neither installed nor carried by the piece.
	**/
	function preset():Null<mdd.song.Instrument> {
		final held = session.song.instrumentAt(session.song.rack[session.part.index()]);
		return held == null ? null : session.loadedFrom(held);
	}

	/**
		Puts a dial, or the whole shape, back to what the preset the channel was loaded from holds,
		which is what a right click asks for. A step is one of a shape rather than a parameter of
		its own, so the shape goes back whole.

		@param envelope The envelope being edited.
		@param px Where the press was, across.
		@param py Where it was, down.
		@return Whether the press was taken.
	**/
	function restores(envelope:Envelope, px:Float, py:Float):Bool {
		final source = preset();
		final held = source == null ? null : source.envelope;

		if (held == null) {
			session.says(Locale.SAID_NO_PRESET);
			return true;
		}

		final turned = dialAt(px, py);

		if (turned >= 0) {
			session.does(new mdd.song.edit.SetEnvelopeDial(envelope, turned, dialOf(held, turned)));
			session.says(Locale.SAID_PRESET_AGAIN, translate(DIAL_NAMES[turned]), source.name);

			invalidate();
			return true;
		}

		if (py < dialsTop()) return false;

		final steps:Array<Int> = [];
		for (value in held.steps) steps.push(value);

		session.does(new mdd.song.edit.DrawEnvelope(envelope, steps));
		session.says(Locale.SAID_PRESET_AGAIN, translate(Locale.PSG_STEPS), source.name);

		invalidate();
		return true;
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

	/**
		@param envelope The envelope.
		@param which Which dial.
		@return What it holds.
	**/
	public function dialOf(envelope:Envelope, which:Int):Int {
		return envelope.dial(which);
	}

	/**
		Turns one dial, clamped to what it takes.

		@param envelope The envelope.
		@param which Which dial.
		@param value What to turn it to.
	**/
	public function turnTo(envelope:Envelope, which:Int, value:Int):Void {
		envelope.turns(which, value);
	}

	function dialSpan(which:Int):Float {
		return Envelope.mostDial(which);
	}

	function stepWide():Float {
		return width / STEPS;
	}

	function stepAt(px:Float):Int {
		final at = Std.int((px - x) / stepWide());
		return at < 0 || at >= STEPS ? -1 : at;
	}

	function levelAt(py:Float, top:Float, tall:Float):Int {
		final part = (py - top) / tall;
		final level = Math.round(part * 15);

		return level < 0 ? 0 : (level > 15 ? 15 : level);
	}

	/**
		Where a dial would stand if its bar reached a point, which is what dragging
		one sets it to.

		@param px A point, across.
		@param which Which dial.
		@return The value that point stands for.
	**/
	function dialValueAt(px:Float, which:Int):Int {
		final root = root();
		if (root == null) return 0;

		final metrics = root.metrics;
		final room = (width - metrics.inset * 2) / dialCount();
		final left = x + metrics.inset + which * room;
		final wide = room - metrics.unit;
		final span = dialSpan(which);

		if (wide <= 0 || span <= 0) return 0;

		var part = (px - left) / wide;

		if (part < 0) part = 0;
		if (part > 1) part = 1;

		return Math.round(part * span);
	}

	override function took(event:Input):Bool {
		final envelope = envelope();
		if (envelope == null) return false;

		switch (event.kind) {
			case Kind.PointerDown:
				if (event.button == Pointer.Right) return restores(envelope, event.x, event.y);
				if (event.button != Pointer.Left) return false;

				final turned = dialAt(event.x, event.y);

				if (turned >= 0) {
					turning = turned;
					grabWas = dialOf(envelope, turned);
					dial = turned;
					invalidate();
					return true;
				}

				if (event.y < dialsTop()) return false;

				grabbing = true;
				wereSteps.resize(0);
				for (value in envelope.steps) wereSteps.push(value);

				drew(envelope, event);
				return true;

			case Kind.PointerMove:
				if (turning >= 0) {
					final fine = event.ctrl();

					if (fine != fining) {
						fining = fine;
						fineX = event.x;
						fineWas = dialOf(envelope, turning);
					}

					turnTo(envelope, turning, fining
						? fineWas + Std.int((event.x - fineX) / FINE)
						: dialValueAt(event.x, turning));

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
					final now = dialOf(envelope, turning);

					if (now != grabWas) {
						envelope.turns(turning, grabWas);
						session.does(new mdd.song.edit.SetEnvelopeDial(envelope, turning, now));
					}

					turning = -1;
					fining = false;
					return true;
				}

				if (!grabbing) return false;

				grabbing = false;
				strokeEnded(envelope);
				return true;

			case Kind.Wheel:
				final turned = dialAt(event.x, event.y);
				if (turned < 0) return false;

				session.does(new mdd.song.edit.SetEnvelopeDial(envelope, turned,
					dialOf(envelope, turned) + Std.int(event.dy)));

				invalidate();
				return true;

			case _:
		}

		return false;
	}

	function graphTall():Float {
		final root = root();
		if (root == null) return 220;

		final room = height - head() - root.metrics.gap;
		final most = root.metrics.whole(240);

		return room > most ? most : room;
	}

	/**
		Puts the stroke that has just ended on the undo stack as one step, by taking
		the steps back to what they were at the press and letting the command draw
		them again. They were written to live so the chips could be heard following
		the pointer.

		@param envelope The envelope that was drawn on.
	**/
	function strokeEnded(envelope:Envelope):Void {
		final now = envelope.steps.copy();

		if (now.length == wereSteps.length) {
			var same = true;
			for (index in 0...now.length) {
				if (now[index] != wereSteps[index]) same = false;
			}

			if (same) return;
		}

		session.holds();
		envelope.steps.resize(0);
		for (value in wereSteps) envelope.steps.push(value);
		session.frees();

		session.does(new mdd.song.edit.DrawEnvelope(envelope, now));
	}

	function drew(envelope:Envelope, event:Input):Void {
		final at = stepAt(event.x);
		if (at < 0) return;

		final top = y + head();
		final tall = graphTall();

		session.holds();
		while (envelope.steps.length <= at) envelope.steps.push(0);
		envelope.steps[at] = levelAt(event.y, top, tall);
		session.frees();

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
			x, y, width, metrics.head);

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
				paint.roundedRect(left, top, wide, tall, metrics.radiusSmall, colour, 0.45,
					part);
			}

			paint.outline(left, top, wide, tall, which == dial ? theme.accent : theme.frame,
				metrics.whole(1), 1, metrics.radiusSmall);

			final line = top + (tall - font.height) * 0.5 + font.ascent;
			final said = which == LOOP && value < 0 ? translate(Locale.PSG_NO_LOOP)
				: Std.string(value);

			paint.fitted(font, metrics.condensed, translate(DIAL_NAMES[which]), "",
				left + metrics.unit, top + tall * 0.5,
				wide - metrics.unit * 2 - font.measure(said) - metrics.gap, theme.dim, 0.85);
			paint.textRight(said, left + wide - metrics.unit, line, theme.ink);
		}
	}
}
