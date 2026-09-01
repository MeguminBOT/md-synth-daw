package mdd.view;

import haxe.ds.Vector;
import mdd.song.Part;
import mdd.ui.Colour;
import mdd.ui.Input;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective
final class Scope extends Widget {
	public static inline final ROWS = 6;
	public static inline final COLUMNS = 2;
	public static inline final SPAN = 512;

	static final ORDER:Vector<Int> = Vector.fromArrayCopy([
		0, 6, 1, 7, 2, 8, 3, 9, 4, 10, 5, 5
	]);

	public final session:Session;

	public final traces:Vector<Float> = new Vector<Float>(Part.COUNT * SPAN);
	public final written:Vector<Int> = new Vector<Int>(Part.COUNT);
	public final notes:Vector<Int> = new Vector<Int>(Part.COUNT);

	public var painted(default, null):Int = 0;

	final line:Vector<Float> = new Vector<Float>(SPAN * 2);

	public function new(session:Session) {
		super();
		this.session = session;

		opaque = true;

		for (i in 0...traces.length) traces[i] = 0;
		for (i in 0...Part.COUNT) {
			written[i] = 0;
			notes[i] = -1;
		}
	}

	public function feed(part:Int, value:Float):Void {
		final at = part * SPAN + written[part];

		traces[at] = value;
		written[part] = (written[part] + 1) % SPAN;
	}

	public function sang(part:Int, note:Int):Void {
		notes[part] = note;
	}

	function trigger(part:Int):Int {
		final base = part * SPAN;
		final from = written[part];

		var last = traces[base + from];

		for (step in 1...SPAN) {
			final at = (from + step) % SPAN;
			final now = traces[base + at];

			if (last < 0 && now >= 0) return at;
			last = now;
		}

		return from;
	}

	function loudest(part:Int):Float {
		final base = part * SPAN;
		var most = 0.0;

		for (i in 0...SPAN) {
			final value = traces[base + i] < 0 ? -traces[base + i] : traces[base + i];
			if (value > most) most = value;
		}

		return most;
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;

		paint.rect(x, y, width, height, theme.ground);
		painted = 0;

		final wide = width / COLUMNS;
		final tall = height / ROWS;
		final font = metrics.small == null ? metrics.body : metrics.small;

		for (cell in 0...ROWS * COLUMNS) {
			final part = ORDER[cell];
			if (cell == 11) continue;

			final column = cell % COLUMNS;
			final row = Std.int(cell / COLUMNS);

			lane(paint, theme, metrics, font, part, x + column * wide, y + row * tall, wide, tall);
		}
	}

	function lane(paint:Paint, theme:Theme, metrics:Metrics, font:mdd.ui.Font, part:Int,
			left:Float, top:Float, wide:Float, tall:Float):Void {
		final inset = metrics.unit;
		final box = metrics.whole(1);

		paint.rect(left + inset, top + inset, wide - inset * 2, tall - inset * 2, theme.panel);
		paint.outline(left + inset, top + inset, wide - inset * 2, tall - inset * 2, theme.frame,
			box);

		final middle = top + tall * 0.5;
		final from = left + inset + metrics.unit;
		final across = wide - inset * 2 - metrics.unit * 2;

		paint.rect(from, middle, across, box, theme.frame, 0.6);

		paint.reface(font);
		paint.text(nameOf(part), left + inset + metrics.unit * 2,
			top + inset + metrics.unit + font.ascent, theme.dim, 0.8);

		final peak = loudest(part);

		if (peak <= 0.0005) return;

		final gain = (tall * 0.5 - inset * 2) / peak;
		final base = part * SPAN;
		final at = trigger(part);
		final steps = Std.int(across);
		final many = steps > SPAN ? SPAN : steps;

		for (i in 0...many) {
			final value = traces[base + (at + i) % SPAN];

			line[i * 2] = from + i * across / many;
			line[i * 2 + 1] = middle - value * gain;
		}

		painted++;
		paint.polyline(line, many, metrics.whole(1.5), theme.part(part), 0.95);

		if (notes[part] >= 0) {
			paint.textRight(spelt(notes[part]), left + wide - inset - metrics.unit * 2,
				top + inset + metrics.unit + font.ascent, theme.part(part), 0.9);
		}
	}

	static function nameOf(part:Int):String {
		final held:Part = part;
		return held.name();
	}

	static final NAMES:Array<String> = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A",
		"A#", "B"];

	public static function spelt(note:Int):String {
		if (note < 0 || note > 127) return "";
		return NAMES[note % 12] + (Std.int(note / 12) - 1);
	}
}
