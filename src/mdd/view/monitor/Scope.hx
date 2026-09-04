package mdd.view.monitor;

import haxe.ds.Vector;
import mdd.app.Locale;
import mdd.app.Session;
import mdd.song.Part;
import mdd.ui.Panel;
import mdd.ui.control.Choice;
import mdd.ui.control.Menu;
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
	public static inline final BARS = 24;

	public static inline final WAVEFORM = 0;
	public static inline final SPECTRUM = 1;

	static final ORDER:Vector<Int> = Vector.fromArrayCopy([
		0, 6, 1, 7, 2, 8, 3, 9, 4, 10, 5, 5
	]);

	public final session:Session;

	public final traces:Vector<Float> = new Vector<Float>(Part.COUNT * SPAN);
	public final written:Vector<Int> = new Vector<Int>(Part.COUNT);
	public final notes:Vector<Int> = new Vector<Int>(Part.COUNT);

	public var painted(default, null):Int = 0;
	public var showing(default, null):Int = WAVEFORM;

	var menu:Null<Menu> = null;

	final line:Vector<Float> = new Vector<Float>(SPAN * 2);
	final bins:Vector<Float> = new Vector<Float>(BARS);
	final turns:Vector<Float> = new Vector<Float>(BARS * 2);

	public function new(session:Session) {
		super();
		this.session = session;

		opaque = true;

		for (i in 0...traces.length) traces[i] = 0;
		for (i in 0...BARS) {
			bins[i] = 0;
			final cycles = Math.round(2 * Math.pow(80, i / (BARS - 1.0)));
			turns[i * 2] = Math.cos(Math.PI * 2 * cycles / SPAN);
			turns[i * 2 + 1] = Math.sin(Math.PI * 2 * cycles / SPAN);
		}

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

	public function shows(which:Int):Void {
		if (which == showing) return;

		showing = which;
		invalidate();
	}

	public function head():Float {
		final root = root();
		return root == null ? 26 : root.metrics.head;
	}

	public function laneAt(px:Float, py:Float):Int {
		final top = head();
		if (py < y + top) return -1;

		final wide = width / COLUMNS;
		final tall = (height - top) / ROWS;
		if (wide <= 0 || tall <= 0) return -1;

		final column = Std.int((px - x) / wide);
		final row = Std.int((py - y - top) / tall);

		if (column < 0 || column >= COLUMNS || row < 0 || row >= ROWS) return -1;

		final cell = row * COLUMNS + column;
		if (cell == 11) return -1;

		return ORDER[cell];
	}

	public function switchAt(px:Float, py:Float):Int {
		final root = root();
		if (root == null || py < y || py >= y + head()) return -1;

		final metrics = root.metrics;
		final wide = metrics.whole(76);
		final left = x + width - metrics.inset - wide * 2;

		if (px < left || px >= left + wide * 2) return -1;
		return px < left + wide ? WAVEFORM : SPECTRUM;
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				final which = switchAt(event.x, event.y);

				if (which >= 0) {
					shows(which);
					return true;
				}

				final part = laneAt(event.x, event.y);
				if (part < 0) return false;

				if (event.button == Pointer.Right) {
					popped(part, event.x, event.y);
					return true;
				}

				session.choose(part);
				return true;

			case _:
		}

		return false;
	}

	function popped(part:Int, px:Float, py:Float):Void {
		final root = root();
		if (root == null) return;

		final song = session.song;
		menu = new Menu();

		fires(menu.offer(new Choice(translate(song.soloed[part]
			? Locale.RACK_UNSOLO : Locale.RACK_SOLO))), function():Void {
			song.soloed[part] = !song.soloed[part];
			session.changed();
		});

		fires(menu.offer(new Choice(translate(song.muted[part]
			? Locale.RACK_UNMUTE : Locale.RACK_MUTE))), function():Void {
			song.muted[part] = !song.muted[part];
			session.changed();
		});

		menu.divide();

		fires(menu.offer(new Choice(translate(Locale.SCOPE_WAVEFORM))), function():Void
			shows(WAVEFORM));
		fires(menu.offer(new Choice(translate(Locale.SCOPE_SPECTRUM))), function():Void
			shows(SPECTRUM));

		menu.divide();

		fires(menu.offer(new Choice(translate(Locale.SCOPE_INSPECT))), function():Void
			session.choose(part));

		root.pop(menu, px, py, this);
	}

	function fires(choice:Choice, what:Void -> Void):Void {
		choice.onFire = function(from:Choice):Void what();
	}

	function bands(part:Int):Float {
		final base = part * SPAN;
		final from = written[part];
		var most = 0.0;

		for (bin in 0...BARS) {
			final cosStep = turns[bin * 2];
			final sinStep = turns[bin * 2 + 1];

			var cosNow = 1.0;
			var sinNow = 0.0;
			var real = 0.0;
			var imaginary = 0.0;

			for (step in 0...SPAN) {
				final value = traces[base + (from + step) % SPAN];

				real += value * cosNow;
				imaginary += value * sinNow;

				final held = cosNow * cosStep - sinNow * sinStep;
				sinNow = cosNow * sinStep + sinNow * cosStep;
				cosNow = held;
			}

			final power = Math.sqrt(real * real + imaginary * imaginary) / SPAN;
			bins[bin] = power;
			if (power > most) most = power;
		}

		return most;
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
		Panel.band(paint, theme, metrics, x, y, width, head());
		painted = 0;

		final top = head();
		final wide = width / COLUMNS;
		final tall = (height - top) / ROWS;
		final font = metrics.small == null ? metrics.body : metrics.small;

		for (cell in 0...ROWS * COLUMNS) {
			final part = ORDER[cell];
			if (cell == 11) continue;

			final column = cell % COLUMNS;
			final row = Std.int(cell / COLUMNS);

			lane(paint, theme, metrics, font, part, x + column * wide, y + top + row * tall,
				wide, tall);
		}

		switcher(paint, theme, metrics, font, top);
	}

	function switcher(paint:Paint, theme:Theme, metrics:Metrics, font:mdd.ui.Font,
			top:Float):Void {
		final wide = metrics.whole(76);
		final tall = metrics.whole(20);
		final left = x + width - metrics.inset - wide * 2;
		final at = y + (top - tall) * 0.5;
		final line = at + (tall - font.height) * 0.5 + font.ascent;

		paint.reface(font);
		paint.roundedRect(left, at, wide * 2, tall, metrics.radiusRow, theme.raise1);
		paint.roundedRect(left + wide * showing, at, wide, tall, metrics.radiusRow,
			theme.accent, 0.85);

		paint.textCentred(translate(Locale.SCOPE_WAVEFORM), left + wide * 0.5, line,
			showing == WAVEFORM ? theme.ink : theme.dim, 0.75);
		paint.textCentred(translate(Locale.SCOPE_SPECTRUM), left + wide * 1.5, line,
			showing == SPECTRUM ? theme.ink : theme.dim, 0.75);
	}

	function lane(paint:Paint, theme:Theme, metrics:Metrics, font:mdd.ui.Font, part:Int,
			left:Float, top:Float, wide:Float, tall:Float):Void {
		final inset = metrics.unit;
		final box = metrics.whole(1);

		paint.roundedRect(left + inset, top + inset, wide - inset * 2, tall - inset * 2,
			metrics.radiusSmall, theme.panel);
		paint.outline(left + inset, top + inset, wide - inset * 2, tall - inset * 2, theme.frame,
			box, 1, metrics.radiusSmall);

		final middle = top + tall * 0.5;
		final from = left + inset + metrics.unit;
		final across = wide - inset * 2 - metrics.unit * 2;

		paint.rect(from, middle, across, box, theme.frame, 0.6);

		paint.reface(font);
		paint.text(nameOf(part), left + inset + metrics.unit * 2,
			top + inset + metrics.unit + font.ascent, theme.dim, 0.8);

		final peak = loudest(part);

		if (peak <= 0.0005) return;

		final reach = tall * 0.5 - inset * 2;

		if (showing == SPECTRUM) {
			final most = bands(part);
			if (most <= 0) return;

			final step = across / BARS;
			final stalk = step * 0.62;
			final floor = middle + reach;

			for (bin in 0...BARS) {
				final part2 = bins[bin] / most;
				final high = reach * 2 * part2;
				if (high < 1) continue;

				paint.rect(from + bin * step, floor - high, stalk, high, theme.part(part), 0.9);
			}

			painted++;
			return;
		}

		paint.rect(from, middle, across, metrics.whole(1), theme.frame, 0.5);

		final gain = reach / peak;
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
