package mdd.view;

import haxe.ds.Vector;
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

	public final session:Session;

	public var held(default, null):Int = -1;
	public var slot(default, null):Int = -1;

	final points:Vector<Float> = new Vector<Float>(64);

	var grabbing:Int = -1;
	var grabAt:Float = 0;
	var grabWas:Int = 0;

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

	function curve():Float {
		final root = root();
		return root == null ? 44 : root.metrics.whole(44);
	}

	function rowsTop():Float {
		return y + head() + curve();
	}

	function rowTall():Float {
		final root = root();
		return root == null ? 22 : root.metrics.whole(22);
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

				if (grabbing < 0) return false;

				final by = Std.int((grabAt - event.y) / (event.ctrl() ? 8 : 2));
				setTo(patch, Std.int(grabbing / NAMES.length), grabbing % NAMES.length,
					grabWas + by);

				invalidate();
				return true;

			case Kind.PointerUp:
				if (grabbing < 0) return false;

				grabbing = -1;
				session.changed();
				return true;

			case Kind.Wheel:
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
			paint.text(session.part.name() + " " + translate(Locale.PANEL_NOT_FM), x + metrics.inset,
				y + metrics.inset + small.ascent, theme.dim);
			return;
		}

		paint.text(session.part.name() + "   algorithm " + patch.algorithm + "   feedback "
			+ patch.feedback, x + metrics.inset, y + metrics.gap + small.ascent, theme.dim);

		routing(paint, theme, metrics, patch);
		envelopes(paint, theme, metrics, patch);
		slots(paint, theme, metrics, patch);
	}

	function routing(paint:Paint, theme:Theme, metrics:Metrics, patch:Patch):Void {
		final top = y + metrics.whole(26);
		final tall = head() - metrics.whole(34);
		final box = metrics.whole(34);
		final gap = (width - metrics.inset * 2 - box * 4) / 3;
		final colour = theme.part(session.part.index());
		final font = metrics.small == null ? metrics.body : metrics.small;

		final wires = ROUTES[patch.algorithm & 7];

		for (i in 0...Std.int(wires.length / 2)) {
			final from = x + metrics.inset + wires[i * 2] * (box + gap) + box * 0.5;
			final to = x + metrics.inset + wires[i * 2 + 1] * (box + gap) + box * 0.5;

			paint.line(from, top + tall * 0.5, to, top + tall * 0.5, metrics.whole(1),
				theme.frame);
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

			final points = new haxe.ds.Vector<Float>(10);
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

		for (slot in 0...Patch.SLOTS) {
			final left = x + slot * wide;

			for (row in 0...NAMES.length) {
				final at = top + row * tall;
				if (at > y + height) break;

				final field = slot * NAMES.length + row;

				if (field == held) {
					paint.roundedRect(left + 1, at, wide - 2, tall - 1, metrics.radiusSmall,
						theme.accent, Theme.SELECT);
				} else if ((row & 1) == 0) {
					paint.rect(left + 1, at, wide - 2, tall - 1, theme.ink, 0.02);
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
