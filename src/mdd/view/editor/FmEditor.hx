package mdd.view.editor;

import haxe.ds.Vector;
import mdd.app.Locale;
import mdd.app.Session;
import mdd.song.Instrument;
import mdd.song.Patch;
import mdd.ui.Colour;
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
	The FM operator editor: four operators of ten fields each, the four channel dials,
	the algorithm drawn as wires, and an envelope per operator.

	The algorithm is drawn as separate wires rather than one line through every box, so
	which operator modulates which is visible instead of implied. Every field says the
	register it writes, the raw value and what that value means, which is the whole
	reason a tooltip is worth having here.
**/
final class FmEditor extends Widget {
	static final NAMES:Array<String> = Patch.NAMES;

	static final SPELT:Array<String> = Patch.SPELT;

	static final BASES:Array<Int> = [0x40, 0x50, 0x60, 0x80, 0x70, 0x80, 0x30, 0x30, 0x50, 0x90];

	static final GROUP:Array<Int> = [0, 2, 1, 3];

	static final ROUTES:Array<Array<Int>> = [
		[0, 1, 1, 2, 2, 3],
		[0, 2, 1, 2, 2, 3],
		[0, 3, 1, 2, 2, 3],
		[0, 1, 1, 3, 2, 3],
		[0, 1, 2, 3],
		[0, 1, 0, 2, 0, 3],
		[0, 1],
		[]
	];

	/**
		Dial: which of the eight operator wirings.
	**/
	public static inline final ALGORITHM = Patch.ALGORITHM;

	/**
		Dial: how much operator one feeds back.
	**/
	public static inline final FEEDBACK = Patch.FEEDBACK;

	/**
		Dial: how far the LFO swings the amplitude.
	**/
	public static inline final AMS = Patch.AMS;

	/**
		Dial: how far it swings the pitch.
	**/
	public static inline final PMS = Patch.PMS;

	/**
		How many dials there are.
	**/
	public static inline final DIALS = Patch.DIALS;

	static final DIAL_NAMES:Array<String> = Patch.DIAL_NAMES;

	static final DIAL_SPELT:Array<String> = Patch.DIAL_SPELT;

	/**
		The session to read.
	**/
	public final session:Session;

	/**
		Which field the pointer is over, or -1.
	**/
	public var held(default, null):Int = -1;

	/**
		Which operator that field belongs to, or -1.
	**/
	public var slot(default, null):Int = -1;

	/**
		Which dial the pointer is over, or -1.
	**/
	public var dial(default, null):Int = -1;

	final points:Vector<Float> = new Vector<Float>(64);

	/**
		How far the pointer moves for one step with the precision key held.
	**/
	static inline final FINE = 4.0;

	var grabbing:Int = -1;
	var fining:Bool = false;
	var fineX:Float = 0;
	var fineWas:Int = 0;
	var grabWas:Int = 0;
	var turning:Int = -1;

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
		@return The patch of the chosen part, or null where it has none.
	**/
	public function patch():Null<Patch> {
		if (!session.part.fm()) return null;

		final instrument = session.song.instrumentAt(session.song.rack[session.part.index()]);
		return instrument == null ? null : instrument.patch;
	}

	function columns():Float {
		return width / Patch.SLOTS;
	}

	function head():Float {
		final root = root();
		return root == null ? 110 : root.metrics.whole(110);
	}

	function dialTall():Float {
		final root = root();
		return root == null ? 22 : root.metrics.whole(22);
	}

	function dialsTop():Float {
		return y + head() - dialTall() - (root() == null ? 4.0 : root().metrics.unit);
	}

	/**
		@param px A point, across.
		@param py A point, down.
		@return Which dial is there, or -1.
	**/
	public function dialAt(px:Float, py:Float):Int {
		final top = dialsTop();
		final tall = dialTall();

		if (py < top || py >= top + tall) return -1;

		final root = root();
		if (root == null) return -1;

		final inset = root.metrics.inset;
		final wide = (width - inset * 2) / DIALS;
		final at = Std.int((px - x - inset) / wide);

		return at < 0 || at >= DIALS ? -1 : at;
	}

	/**
		@param patch The patch being edited.
		@param which Which dial.
		@return What it holds.
	**/
	public function dialOf(patch:Patch, which:Int):Int {
		return patch.dial(which);
	}

	/**
		Turns one dial, through the command stack so it undoes.

		@param patch The patch being edited.
		@param which Which dial.
		@param value What to turn it to.
	**/
	public function turnTo(patch:Patch, which:Int, value:Int):Void {
		patch.turns(which, value);
	}

	function curve():Float {
		final root = root();
		return root == null ? 44 : root.metrics.whole(44);
	}

	function rowsTop():Float {
		return y + head() + curve();
	}

	function rowTall():Float {
		final root = root();
		if (root == null) return 26;

		final metrics = root.metrics;
		final room = (height - head() - curve() - metrics.gap) / NAMES.length;
		final least = metrics.whole(24);
		final most = metrics.whole(40);

		return room < least ? least : (room > most ? most : room);
	}

	/**
		@param row Which field of an operator, 0 to 9.
		@return Where that row sits, down the panel, at its middle.
	**/
	public function rowMiddle(row:Int):Float {
		return rowsTop() + (row + 0.5) * rowTall();
	}

	function fieldAt(px:Float, py:Float):Int {
		if (patch() == null) return -1;

		final wide = columns();
		final column = Std.int((px - x) / wide);
		if (column < 0 || column >= Patch.SLOTS) return -1;

		final row = Std.int((py - rowsTop()) / rowTall());
		if (row < 0 || row >= NAMES.length) return -1;

		return column * NAMES.length + row;
	}

	/**
		@param patch The patch being edited.
		@param slot Which operator, 0 to 3.
		@param row Which field of it, 0 to 9.
		@return What that field holds.
	**/
	public function valueOf(patch:Patch, slot:Int, row:Int):Int {
		return patch.reads(slot, row);
	}

	/**
		@param row Which field of it, 0 to 9.
		@return The largest value it takes, which is the width of its register field.
	**/
	public function most(row:Int):Int {
		return Patch.mostOf(row);
	}

	function setTo(patch:Patch, slot:Int, row:Int, value:Int):Void {
		patch.writes(slot, row, value);
	}

	/**
		@param slot Which operator, 0 to 3.
		@param row Which field of it, 0 to 9.
		@return The register address that field writes, which is what the tooltip shows.
	**/
	public function registerOf(slot:Int, row:Int):Int {
		final group = GROUP[slot];
		return BASES[row] + group * 4 + (session.part.index() % 3);
	}

	/**
		@param patch The patch being edited.
		@param slot Which operator, 0 to 3.
		@param row Which field of it, 0 to 9.
		@return The first line of the tooltip: what the field is called.
	**/
	public function saying(patch:Patch, slot:Int, row:Int):String {
		return SPELT[row] + "   OP" + (slot + 1);
	}

	/**
		@param patch The patch being edited.
		@param slot Which operator, 0 to 3.
		@param row Which field of it, 0 to 9.
		@return The second line: the register, the raw value, and what that value means in decibels
			or in milliseconds.
	**/
	public function detailOf(patch:Patch, slot:Int, row:Int):String {
		final at = registerOf(slot, row);
		final half = session.part.index() >= 3 ? 1 : 0;
		final value = valueOf(patch, slot, row);

		var said = "register " + (half == 1 ? "part 2 " : "") + "$"
			+ StringTools.hex(at, 2) + "   value " + value;

		if (row == 0) said += "   " + shown(-0.75 * value) + " dB";
		else if (row == 3) said += "   " + shown(-3.0 * value) + " dB";
		else if (row == 6) said += "   x" + (value == 0 ? "0.5" : Std.string(value));

		return said;
	}

	static function shown(value:Float):String {
		final held = Math.round(value * 100) / 100;
		return held > 0 ? "+" + held : Std.string(held);
	}

	function described(px:Float, py:Float):Void {
		final patch = patch();
		final field = patch == null ? -1 : fieldAt(px, py);

		if (field < 0) {
			if (tip == "") return;

			tip = "";
			detail = "";
			return;
		}

		final slot = Std.int(field / NAMES.length);
		final row = field % NAMES.length;

		tip = saying(patch, slot, row);
		detail = detailOf(patch, slot, row);
	}

	/**
		Takes the precision key changing mid drag, which has to re-anchor or the
		value jumps by however far the pointer had already travelled.

		@param fine Whether the key is down now.
		@param px Where the pointer is, across.
		@param value What the thing being dragged holds now.
	**/
	function anchored(fine:Bool, px:Float, value:Int):Void {
		if (fine == fining) return;

		fining = fine;
		fineX = px;
		fineWas = value;
	}

	/**
		Where the bar of a field would stand if it reached a point, which is what
		dragging one sets it to. Total level draws backwards, because the register
		attenuates and the bar reads as loudness, and it is read back the same way.

		@param px A point, across.
		@param field Which field the bar belongs to.
		@return The value that point stands for.
	**/
	function valueAt(px:Float, field:Int):Int {
		final row = field % NAMES.length;
		final wide = columns();
		final left = x + Std.int(field / NAMES.length) * wide + 1;
		final room = wide - 2;
		final ceiling = most(row);

		if (room <= 0 || ceiling <= 0) return 0;

		var part = (px - left) / room;

		if (part < 0) part = 0;
		if (part > 1) part = 1;

		return Math.round((row == 0 ? 1 - part : part) * ceiling);
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
		final room = (width - metrics.inset * 2) / DIALS;
		final left = x + metrics.inset + which * room;
		final wide = room - metrics.unit;
		final ceiling = Patch.mostDial(which);

		if (wide <= 0 || ceiling <= 0) return 0;

		var part = (px - left) / wide;

		if (part < 0) part = 0;
		if (part > 1) part = 1;

		return Math.round(part * ceiling);
	}

	/**
		Puts the drag that has just ended on the undo stack as one step, by taking
		the value back to what it was at the press and letting the command set it
		again. The patch was written to live so the chips could be heard following
		the pointer.

		@param patch The patch being edited.
	**/
	function landed(patch:Patch):Void {
		if (turning >= 0) {
			final now = dialOf(patch, turning);

			if (now != grabWas) {
				patch.turns(turning, grabWas);
				session.does(new mdd.song.edit.SetDial(patch, turning, now));
			}

		return;
		}

		if (grabbing < 0) return;

		final slot = Std.int(grabbing / NAMES.length);
		final row = grabbing % NAMES.length;
		final now = valueOf(patch, slot, row);

		if (now == grabWas) return;

		patch.writes(slot, row, grabWas);
		session.does(new mdd.song.edit.SetOperator(patch, slot, row, now));
	}

	override function took(event:Input):Bool {
		final patch = patch();
		if (patch == null) return false;

		switch (event.kind) {
			case Kind.PointerDown:
				if (event.button != Pointer.Left) return false;

				final turned = dialAt(event.x, event.y);

				if (turned >= 0) {
					if (event.clicks >= 2) {
						session.does(new mdd.song.edit.SetDial(patch, turned,
							new Patch().dial(turned)));

						invalidate();
						return true;
					}

					turning = turned;
					grabWas = dialOf(patch, turned);
					dial = turned;
					invalidate();
					return true;
				}

				final field = fieldAt(event.x, event.y);
				if (field < 0) return false;

				if (event.clicks >= 2) {
					final slot = Std.int(field / NAMES.length);
					final row = field % NAMES.length;

					session.does(new mdd.song.edit.SetOperator(patch, slot, row,
						new Patch().reads(slot, row)));

					invalidate();
					return true;
				}

				grabbing = field;
				grabWas = valueOf(patch, Std.int(field / NAMES.length),
					field % NAMES.length);

				held = field;
				slot = Std.int(field / NAMES.length);
				invalidate();
				return true;

			case Kind.PointerMove:
				described(event.x, event.y);

				if (turning >= 0) {
					anchored(event.ctrl(), event.x, dialOf(patch, turning));

					turnTo(patch, turning, fining
						? fineWas + Std.int((event.x - fineX) / FINE)
						: dialValueAt(event.x, turning));

					invalidate();
					return true;
				}

				if (grabbing < 0) return false;

				final slot = Std.int(grabbing / NAMES.length);
				final row = grabbing % NAMES.length;

				anchored(event.ctrl(), event.x, valueOf(patch, slot, row));

				setTo(patch, slot, row, fining
					? fineWas + Std.int((event.x - fineX) / FINE)
					: valueAt(event.x, grabbing));

				invalidate();
				return true;

			case Kind.PointerUp:
				if (turning < 0 && grabbing < 0) return false;

				landed(patch);

				turning = -1;
				grabbing = -1;
				fining = false;
				return true;

			case Kind.Wheel:
				final turned = dialAt(event.x, event.y);

				if (turned >= 0) {
					session.does(new mdd.song.edit.SetDial(patch, turned,
						dialOf(patch, turned) + Std.int(event.dy)));
					invalidate();
					return true;
				}

				final field = fieldAt(event.x, event.y);
				if (field < 0) return false;

				final row = field % NAMES.length;
				final which = Std.int(field / NAMES.length);
				final step = event.ctrl() ? 1 : 4;

				session.does(new mdd.song.edit.SetOperator(patch, which, row,
					valueOf(patch, which, row) + Std.int(event.dy) * step));

				invalidate();
				return true;

			case _:
		}

		return false;
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final patch = patch();

		paint.rect(x, y, width, height, theme.panel);

		final small = metrics.small == null ? metrics.body : metrics.small;
		paint.reface(small);

		if (patch == null) {
			Panel.titled(paint, theme, metrics, session.part.name(), x, y, width, metrics.head);
			paint.reface(small);
			paint.text(translate(Locale.PANEL_NOT_FM), x + metrics.inset,
				y + metrics.head + metrics.gap + small.ascent, theme.dim);
			return;
		}

		Panel.titled(paint, theme, metrics, session.part.name(), x, y, width, metrics.head);
		paint.reface(small);

		routing(paint, theme, metrics, patch);
		dials(paint, theme, metrics, patch);
		envelopes(paint, theme, metrics, patch);
		slots(paint, theme, metrics, patch);
	}

	function dials(paint:Paint, theme:Theme, metrics:Metrics, patch:Patch):Void {
		final font = metrics.small == null ? metrics.body : metrics.small;
		final top = dialsTop();
		final tall = dialTall();
		final room = (width - metrics.inset * 2) / DIALS;
		final colour = theme.part(session.part.index());

		paint.reface(font);

		for (which in 0...DIALS) {
			final left = x + metrics.inset + which * room;
			final wide = room - metrics.unit;
			final value = dialOf(patch, which);
			final part = value / Patch.mostDial(which);

			paint.roundedRect(left, top, wide, tall, metrics.radiusSmall, theme.raise1);

			if (part > 0) {
				paint.roundedRect(left, top, wide, tall, metrics.radiusSmall, colour, 0.45,
					part);
			}

			paint.outline(left, top, wide, tall, which == dial ? theme.accent : theme.frame,
				metrics.whole(1), 1, metrics.radiusSmall);

			final line = top + (tall - font.height) * 0.5 + font.ascent;

			final room = wide - metrics.unit * 2 - font.measure("0") - metrics.gap;
			final named = font.measure(DIAL_SPELT[which]) <= room ? DIAL_SPELT[which]
				: DIAL_NAMES[which];

			paint.text(named, left + metrics.unit, line, theme.dim, 0.85);
			paint.textRight(Std.string(value), left + wide - metrics.unit, line, theme.ink);
		}
	}

	function routing(paint:Paint, theme:Theme, metrics:Metrics, patch:Patch):Void {
		final top = y + metrics.whole(28);
		final tall = dialsTop() - top - metrics.unit;
		final box = metrics.whole(34);
		final gap = (width - metrics.inset * 2 - box * 4) / 3;
		final colour = theme.part(session.part.index());
		final font = metrics.small == null ? metrics.body : metrics.small;

		final wires = ROUTES[patch.algorithm & 7];
		final many = Std.int(wires.length / 2);
		final hair = metrics.whole(2);
		final step = many < 1 ? tall : tall / (many + 1);

		for (i in 0...many) {
			final one = wires[i * 2];
			final two = wires[i * 2 + 1];

			final from = x + metrics.inset + one * (box + gap) + box;
			final to = x + metrics.inset + two * (box + gap);
			final line = top + step * (i + 1) - hair * 0.5;

			paint.rect(from, line, to - from, hair, colour, 0.7);
			paint.circle(to - metrics.whole(3), line + hair * 0.5, metrics.whole(2.5),
				colour, 0.9);
		}

		paint.reface(font);

		for (slot in 0...Patch.SLOTS) {
			final at = x + metrics.inset + slot * (box + gap);
			final carrier = patch.carries(slot);

			paint.roundedRect(at, top, box, tall, metrics.radiusSmall,
				carrier ? colour : theme.raise1, carrier ? 0.35 : 1);
			paint.outline(at, top, box, tall, slot == this.slot ? theme.accent : theme.frame,
				metrics.whole(1), 1, metrics.radiusSmall);

			paint.textCentred("OP" + (slot + 1), at + box * 0.5,
				top + tall * 0.5 - font.height * 0.5 + font.ascent,
				carrier ? theme.ink : theme.dim);

			if (carrier) {
				paint.circle(at + box * 0.5, top + tall - metrics.whole(7), metrics.whole(2.5),
					colour);
			}
		}
	}

	static inline function spanOf(rate:Int):Float {
		return (32 - rate) / 32.0;
	}

	function envelopes(paint:Paint, theme:Theme, metrics:Metrics, patch:Patch):Void {
		final wide = columns();
		final tall = curve();
		final top = y + head();
		final inset = metrics.gap;

		for (slot in 0...Patch.SLOTS) {
			final left = x + slot * wide + inset;
			final room = wide - inset * 2;
			final floor = top + tall - inset;
			final ceiling = top + inset;
			final reach = floor - ceiling;

			paint.rect(left, ceiling, room, reach, theme.sink, 0.5);

			final peak = (127 - patch.totalLevel[slot]) / 127.0;
			final held = patch.sustainLevel[slot] / 15.0;
			final rest = peak * (1 - held);

			var attack = spanOf(patch.attack[slot]);
			var decay = spanOf(patch.decay[slot]);
			var sustain = spanOf(patch.sustain[slot]);
			var release = spanOf(patch.release[slot] * 2);

			final total = attack + decay + sustain + release;
			final scale = total <= 0 ? 0 : room / total;

			final carrier = patch.carries(slot);
			final ink = carrier ? theme.part(session.part.index()) : theme.dim;
			final hair = metrics.whole(2);

			var pen = left;
			var level = 0.0;

			points[0] = pen;
			points[1] = floor;

			pen += attack * scale;
			level = peak;
			points[2] = pen;
			points[3] = floor - reach * level;

			pen += decay * scale;
			level = rest;
			points[4] = pen;
			points[5] = floor - reach * level;

			pen += sustain * scale;
			level = rest * 0.35;
			points[6] = pen;
			points[7] = floor - reach * level;

			pen += release * scale;
			points[8] = pen;
			points[9] = floor;

			paint.polyline(points, 5, hair, ink, carrier ? 1 : 0.7);
		}
	}

	function slots(paint:Paint, theme:Theme, metrics:Metrics, patch:Patch):Void {
		final wide = columns();
		final tall = rowTall();
		final top = rowsTop();
		final font = metrics.mono == null ? metrics.body : metrics.mono;
		final small = metrics.small == null ? metrics.body : metrics.small;
		final colour = theme.part(session.part.index());

		for (slot in 0...Patch.SLOTS) {
			final left = x + slot * wide;

			for (row in 0...NAMES.length) {
				final at = top + row * tall;
				if (at > y + height) break;

				final field = slot * NAMES.length + row;

				if ((row & 1) == 0) {
					paint.rect(left + 1, at, wide - 2, tall - 1, theme.ink, 0.02);
				}

				final ceiling = most(row);
				final value = valueOf(patch, slot, row);
				final part = ceiling <= 0 ? 0.0
					: (row == 0 ? 1 - value / ceiling : value / ceiling);

				if (part > 0.001) {
					paint.rect(left + 1, at, (wide - 2) * part, tall - 1,
						patch.carries(slot) ? colour : theme.dim, 0.22);
				}

				if (field == held) {
					paint.roundedRect(left + 1, at, wide - 2, tall - 1, metrics.radiusSmall,
						theme.accent, Theme.SELECT);
				}
			}
		}

		paint.reface(small);

		final room = wide - metrics.unit * 4 - font.measure("000") - metrics.gap;

		for (slot in 0...Patch.SLOTS) {
			final left = x + slot * wide;

			for (row in 0...NAMES.length) {
				final at = top + row * tall;
				if (at > y + height) break;

				final said = small.measure(SPELT[row]) <= room ? SPELT[row] : NAMES[row];

				paint.text(said, left + metrics.unit * 2,
					at + (tall - small.height) * 0.5 + small.ascent, theme.dim, 0.8);
			}
		}

		paint.reface(font);

		for (slot in 0...Patch.SLOTS) {
			final left = x + slot * wide;

			for (row in 0...NAMES.length) {
				final at = top + row * tall;
				if (at > y + height) break;

				paint.textRight(Std.string(valueOf(patch, slot, row)),
					left + wide - metrics.unit * 2,
					at + (tall - font.height) * 0.5 + font.ascent, theme.ink);
			}
		}
	}
}
