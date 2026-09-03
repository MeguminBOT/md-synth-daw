package mdd.view;

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
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective
final class FmEditor extends Widget {
	static final NAMES:Array<String> = ["TL", "AR", "D1R", "D1L", "D2R", "RR", "MUL", "DT", "RS",
		"SSG"];

	static final SPELT:Array<String> = ["Total level", "Attack rate", "First decay rate",
		"Sustain level", "Second decay rate", "Release rate", "Multiple", "Detune",
		"Rate scaling", "SSG envelope"];

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

	public static inline final ALGORITHM = 0;
	public static inline final FEEDBACK = 1;
	public static inline final AMS = 2;
	public static inline final PMS = 3;
	public static inline final DIALS = 4;

	static final DIAL_NAMES:Array<String> = ["ALG", "FB", "AMS", "PMS"];
	static final DIAL_MOST:Array<Int> = [7, 7, 3, 7];

	public final session:Session;

	public var held(default, null):Int = -1;
	public var slot(default, null):Int = -1;
	public var dial(default, null):Int = -1;

	final points:Vector<Float> = new Vector<Float>(64);

	var grabbing:Int = -1;
	var grabAt:Float = 0;
	var grabWas:Int = 0;
	var turning:Int = -1;

	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;
	}

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

	public function dialOf(patch:Patch, which:Int):Int {
		return switch (which) {
			case ALGORITHM: patch.algorithm;
			case FEEDBACK: patch.feedback;
			case AMS: patch.ams;
			case _: patch.pms;
		}
	}

	public function turnTo(patch:Patch, which:Int, value:Int):Void {
		final most = DIAL_MOST[which];
		final want = value < 0 ? 0 : (value > most ? most : value);

		switch (which) {
			case ALGORITHM: patch.algorithm = want;
			case FEEDBACK: patch.feedback = want;
			case AMS: patch.ams = want;
			case _: patch.pms = want;
		}
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

	public function fieldAt(px:Float, py:Float):Int {
		if (patch() == null) return -1;

		final wide = columns();
		final column = Std.int((px - x) / wide);
		if (column < 0 || column >= Patch.SLOTS) return -1;

		final row = Std.int((py - rowsTop()) / rowTall());
		if (row < 0 || row >= NAMES.length) return -1;

		return column * NAMES.length + row;
	}

	public function valueOf(patch:Patch, slot:Int, row:Int):Int {
		return switch (row) {
			case 0: patch.totalLevel[slot];
			case 1: patch.attack[slot];
			case 2: patch.decay[slot];
			case 3: patch.sustainLevel[slot];
			case 4: patch.sustain[slot];
			case 5: patch.release[slot];
			case 6: patch.multiple[slot];
			case 7: patch.detune[slot];
			case 8: patch.keyScale[slot];
			case _: patch.ssg[slot];
		}
	}

	public function most(row:Int):Int {
		return switch (row) {
			case 0: 127;
			case 1, 2, 4, 5: 31;
			case 3: 15;
			case 6: 15;
			case 7: 7;
			case 8: 3;
			case _: 15;
		}
	}

	public function setTo(patch:Patch, slot:Int, row:Int, value:Int):Void {
		final want = value < 0 ? 0 : (value > most(row) ? most(row) : value);

		switch (row) {
			case 0: patch.totalLevel[slot] = want;
			case 1: patch.attack[slot] = want;
			case 2: patch.decay[slot] = want;
			case 3: patch.sustainLevel[slot] = want;
			case 4: patch.sustain[slot] = want;
			case 5: patch.release[slot] = want;
			case 6: patch.multiple[slot] = want;
			case 7: patch.detune[slot] = want;
			case 8: patch.keyScale[slot] = want;
			case _: patch.ssg[slot] = want;
		}
	}

	public function registerOf(slot:Int, row:Int):Int {
		final group = GROUP[slot];
		return BASES[row] + group * 4 + (session.part.index() % 3);
	}

	public function saying(patch:Patch, slot:Int, row:Int):String {
		return SPELT[row] + "   OP" + (slot + 1);
	}

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

	override function took(event:Input):Bool {
		final patch = patch();
		if (patch == null) return false;

		switch (event.kind) {
			case Kind.PointerDown:
				final turned = dialAt(event.x, event.y);

				if (turned >= 0) {
					turning = turned;
					grabAt = event.x;
					grabWas = dialOf(patch, turned);
					dial = turned;
					invalidate();
					return true;
				}

				final field = fieldAt(event.x, event.y);
				if (field < 0) return false;

				grabbing = field;
				grabAt = event.y;
				grabWas = valueOf(patch, Std.int(field / NAMES.length), field % NAMES.length);

				held = field;
				slot = Std.int(field / NAMES.length);
				invalidate();
				return true;

			case Kind.PointerMove:
				described(event.x, event.y);

				if (turning >= 0) {
					turnTo(patch, turning,
						grabWas + Std.int((event.x - grabAt) / (event.ctrl() ? 24 : 8)));
					invalidate();
					return true;
				}

				if (grabbing < 0) return false;

				final by = Std.int((grabAt - event.y) / (event.ctrl() ? 8 : 2));
				setTo(patch, Std.int(grabbing / NAMES.length), grabbing % NAMES.length,
					grabWas + by);

				invalidate();
				return true;

			case Kind.PointerUp:
				if (turning >= 0) {
					turning = -1;
					session.changed();
					return true;
				}

				if (grabbing < 0) return false;

				grabbing = -1;
				session.changed();
				return true;

			case Kind.Wheel:
				final turned = dialAt(event.x, event.y);

				if (turned >= 0) {
					turnTo(patch, turned, dialOf(patch, turned) + Std.int(event.dy));
					session.changed();
					invalidate();
					return true;
				}

				final field = fieldAt(event.x, event.y);
				if (field < 0) return false;

				final row = field % NAMES.length;
				final which = Std.int(field / NAMES.length);
				final step = event.ctrl() ? 1 : 4;

				setTo(patch, which, row, valueOf(patch, which, row) + Std.int(event.dy) * step);
				session.changed();
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
			Panel.titled(paint, theme, metrics, session.part.name(), x, y, width,
				metrics.whole(22));
			paint.reface(small);
			paint.text(translate(Locale.PANEL_NOT_FM), x + metrics.inset,
				y + metrics.whole(22) + metrics.gap + small.ascent, theme.dim);
			return;
		}

		Panel.titled(paint, theme, metrics, session.part.name(), x, y, width,
			metrics.whole(22));
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
			final part = value / DIAL_MOST[which];

			paint.roundedRect(left, top, wide, tall, metrics.radiusSmall, theme.raise1);

			if (part > 0) {
				paint.roundedRect(left, top, wide * part, tall, metrics.radiusSmall, colour,
					0.45);
			}

			paint.outline(left, top, wide, tall, which == dial ? theme.accent : theme.frame,
				metrics.whole(1));

			final line = top + (tall - font.height) * 0.5 + font.ascent;

			paint.text(DIAL_NAMES[which], left + metrics.unit, line, theme.dim, 0.85);
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
				metrics.whole(1));

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

		for (slot in 0...Patch.SLOTS) {
			final left = x + slot * wide;

			for (row in 0...NAMES.length) {
				final at = top + row * tall;
				if (at > y + height) break;

				paint.text(NAMES[row], left + metrics.unit * 2,
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
