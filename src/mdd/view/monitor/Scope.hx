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

/**
	The scope: one lane per part, showing either the waveform or the spectrum.

	Every sample the chips make reaches it. The speed decides how much time a lane shows and
	the accuracy how many of those samples a lane keeps, so a fast, coarse scope costs little
	to draw and a slow, fine one shows every edge a bright patch has.
**/
final class Scope extends Widget {
	/**
		How many lanes are stacked down.
	**/
	public static inline final ROWS = 6;

	/**
		How many are laid out across.
	**/
	public static inline final COLUMNS = 2;

	/**
		How many samples one lane holds, which is the longest window any speed and accuracy can
		ask for with as much again behind it to look for a trigger in.
	**/
	public static inline final SPAN = 16384;

	/**
		The most samples the spectrum is worked out over. A longer window is read from its
		newest end, because the bars barely change past this and the cost grows with every
		sample.
	**/
	public static inline final ANALYSED = 2048;

	/**
		The most columns a lane is drawn in, which bounds the points one trace can take.
	**/
	static inline final FIT = 4096;

	/**
		The lowest bar, in hertz.
	**/
	static inline final LOWEST = 40.0;

	/**
		The highest bar, in hertz, unless half the rate a lane holds is lower.
	**/
	static inline final HIGHEST = 8000.0;

	/**
		How much time a lane shows at each speed, in milliseconds, fastest first.
	**/
	public static final SPEEDS:Array<Int> = [10, 20, 40, 80, 160];

	/**
		The speed a scope starts at, which is close to the 43 ms a lane always showed.
	**/
	public static inline final SPEED = 2;

	/**
		How many captured samples a lane steps over at each accuracy, lowest first.
	**/
	public static final STRIDES:Array<Int> = [4, 2, 1];

	/**
		The accuracy a scope starts at, which keeps one sample in four as the scope always did.
	**/
	public static inline final ACCURACY = 0;

	static final ACCURACIES:Array<Locale> = [Locale.SCOPE_LOW, Locale.SCOPE_MEDIUM,
		Locale.SCOPE_HIGH];

	/**
		How many bars the spectrum is drawn as.
	**/
	public static inline final BARS = 24;

	/**
		Showing: the samples over time.
	**/
	public static inline final WAVEFORM = 0;

	/**
		Showing: what is in them.
	**/
	public static inline final SPECTRUM = 1;

	static final ORDER:Vector<Int> = Vector.fromArrayCopy([
		0, 6, 1, 7, 2, 8, 3, 9, 4, 10, 5, 5
	]);

	/**
		The session to read.
	**/
	public final session:Session;

	final traces:Vector<Float> = new Vector<Float>(Part.COUNT * SPAN);

	/**
		How many samples each lane holds.
	**/
	public final written:Vector<Int> = new Vector<Int>(Part.COUNT);

	/**
		Which note each part is sounding, for the label.
	**/
	public final notes:Vector<Int> = new Vector<Int>(Part.COUNT);

	/**
		How many lanes the last frame drew.
	**/
	public var painted(default, null):Int = 0;

	/**
		Which of the two is shown.
	**/
	public var showing(default, null):Int = WAVEFORM;

	/**
		Which of `SPEEDS` is in use.
	**/
	public var speed(default, null):Int = SPEED;

	/**
		Which of `STRIDES` is in use.
	**/
	public var accuracy(default, null):Int = ACCURACY;

	/**
		The rate captured samples arrive at, which is the rate the device plays at.
	**/
	public var rate(default, null):Int = 48000;

	/**
		Called when the speed or the accuracy is changed from the menu, so both can be kept.
	**/
	public var onChange:Null<() -> Void> = null;

	var menu:Null<Menu> = null;

	final skipped:Vector<Int> = new Vector<Int>(Part.COUNT);
	final line:Vector<Float> = new Vector<Float>(SPAN);
	final bins:Vector<Float> = new Vector<Float>(BARS);
	final turns:Vector<Float> = new Vector<Float>(BARS * 2);

	/**
		Builds the scope.

		@param session The session to read.
	**/
	public function new(session:Session) {
		super();
		this.session = session;

		opaque = true;

		for (i in 0...traces.length) traces[i] = 0;
		for (i in 0...BARS) bins[i] = 0;

		for (i in 0...Part.COUNT) {
			written[i] = 0;
			notes[i] = -1;
			skipped[i] = 0;
		}

		tuned();
	}

	/**
		Adds one captured sample to a lane, keeping one in however many the accuracy steps over.

		@param part Which part.
		@param value The sample.
	**/
	public function feed(part:Int, value:Float):Void {
		final skip = skipped[part] + 1;

		if (skip < STRIDES[accuracy]) {
			skipped[part] = skip;
			return;
		}

		skipped[part] = 0;

		final at = part * SPAN + written[part];

		traces[at] = value;
		written[part] = (written[part] + 1) % SPAN;
	}

	/**
		Says which note a part is sounding.

		@param part Which part.
		@param note A MIDI note number, or -1 for none.
	**/
	public function sang(part:Int, note:Int):Void {
		notes[part] = note;
	}

	/**
		@return How many samples a lane shows at the speed and accuracy in use, at the rate the
			device plays at. Never more than half of what a lane holds, so there is always room
			behind the window to look for a trigger.
	**/
	public function window():Int {
		final many = Math.round(SPEEDS[speed] * rate / (1000.0 * STRIDES[accuracy]));
		final most = Std.int(SPAN / 2);

		return many < 2 ? 2 : (many > most ? most : many);
	}

	/**
		Where a lane's window starts: the latest upward crossing through nought that still
		leaves a whole window of samples after it, so a steady tone stands still, or the latest
		start there is where no crossing falls within one window of it.

		@param part Which part.
		@return A place in the lane.
	**/
	public function startOf(part:Int):Int {
		final many = window();
		final base = part * SPAN;
		final latest = (written[part] - many + SPAN * 2) % SPAN;

		var at = latest;

		for (step in 0...many) {
			final before = at == 0 ? SPAN - 1 : at - 1;

			if (traces[base + before] < 0 && traces[base + at] >= 0) return at;

			at = before;
		}

		return latest;
	}

	/**
		@param part Which part.
		@param at A place in the lane, which wraps.
		@return The sample held there.
	**/
	public inline function sampleAt(part:Int, at:Int):Float {
		return traces[part * SPAN + ((at % SPAN) + SPAN) % SPAN];
	}

	/**
		Changes how much time a lane shows.

		@param which One of `SPEEDS`, by index, held to the nearest where it is outside them.
	**/
	public function paces(which:Int):Void {
		speed = which < 0 ? 0 : (which >= SPEEDS.length ? SPEEDS.length - 1 : which);
		invalidate();
	}

	/**
		Changes how many captured samples a lane keeps, and moves the bars to match.

		The lanes are cleared, because samples kept at one accuracy drawn beside samples kept at
		another read as a trace that jumps in pitch halfway across.

		@param which One of `STRIDES`, by index, held to the nearest where it is outside them.
	**/
	public function refines(which:Int):Void {
		final want = which < 0 ? 0 : (which >= STRIDES.length ? STRIDES.length - 1 : which);
		if (want == accuracy) return;

		accuracy = want;

		for (i in 0...traces.length) traces[i] = 0;
		for (i in 0...Part.COUNT) skipped[i] = 0;

		tuned();
		invalidate();
	}

	/**
		Tells the scope the rate its samples arrive at, which the device decides.

		@param hertz The rate.
	**/
	public function rated(hertz:Int):Void {
		if (hertz <= 0 || hertz == rate) return;

		rate = hertz;
		tuned();
		invalidate();
	}

	/**
		Places the bars at fixed frequencies for the rate a lane now holds, so the axis stays put
		when the accuracy changes. They run from `LOWEST` to `HIGHEST`, spaced evenly in pitch,
		with the top held below half that rate.
	**/
	function tuned():Void {
		final held = rate / STRIDES[accuracy];
		final ceiling = held * 0.45 < HIGHEST ? held * 0.45 : HIGHEST;

		for (bin in 0...BARS) {
			final hertz = LOWEST * Math.pow(ceiling / LOWEST, bin / (BARS - 1.0));
			final turn = 2 * Math.PI * hertz / held;

			turns[bin * 2] = Math.cos(turn);
			turns[bin * 2 + 1] = Math.sin(turn);
		}
	}

	/**
		Switches between the waveform and the spectrum.

		@param which `WAVEFORM` or `SPECTRUM`.
	**/
	public function shows(which:Int):Void {
		if (which == showing) return;

		showing = which;
		invalidate();
	}

	/**
		@return How tall the title band is.
	**/
	public function head():Float {
		final root = root();
		return root == null ? 26 : root.metrics.head;
	}

	/**
		@param px A point, across.
		@param py A point, down.
		@return Which part lane is there, or -1.
	**/
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

	function switchAt(px:Float, py:Float):Int {
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
			session.does(new mdd.song.edit.SoloPart(part, !song.soloed[part]));
		});

		fires(menu.offer(new Choice(translate(song.muted[part]
			? Locale.RACK_UNMUTE : Locale.RACK_MUTE))), function():Void {
			session.does(new mdd.song.edit.MutePart(part, !song.muted[part]));
		});

		menu.divide();

		fires(menu.offer(new Choice(translate(Locale.SCOPE_WAVEFORM))), function():Void
			shows(WAVEFORM));
		fires(menu.offer(new Choice(translate(Locale.SCOPE_SPECTRUM))), function():Void
			shows(SPECTRUM));

		menu.divide();

		final speeds = new Menu();

		for (index in 0...SPEEDS.length) {
			fires(speeds.offer(new Choice(SPEEDS[index] + " ms")), function():Void {
				paces(index);
				if (onChange != null) onChange();
			});
		}

		final accuracies = new Menu();

		for (index in 0...STRIDES.length) {
			fires(accuracies.offer(new Choice(translate(ACCURACIES[index]))), function():Void {
				refines(index);
				if (onChange != null) onChange();
			});
		}

		menu.offer(new Choice(translate(Locale.SCOPE_SPEED) + "  " + SPEEDS[speed] + " ms"))
			.submenu = speeds;
		menu.offer(new Choice(translate(Locale.SCOPE_ACCURACY) + "  "
			+ translate(ACCURACIES[accuracy]))).submenu = accuracies;

		menu.divide();

		fires(menu.offer(new Choice(translate(Locale.SCOPE_INSPECT))), function():Void
			session.choose(part));

		root.pop(menu, px, py, this);
	}

	/**
		Works out how much of each bar's frequency is in a run of samples, into `bins`.

		@param part Which part.
		@param start Where the run starts in the lane.
		@param many How long it is.
		@return The largest bar.
	**/
	function bands(part:Int, start:Int, many:Int):Float {
		final base = part * SPAN;
		var most = 0.0;

		for (bin in 0...BARS) {
			final cosStep = turns[bin * 2];
			final sinStep = turns[bin * 2 + 1];

			var cosNow = 1.0;
			var sinNow = 0.0;
			var real = 0.0;
			var imaginary = 0.0;
			var at = start;

			for (step in 0...many) {
				final value = traces[base + at];

				at++;
				if (at >= SPAN) at = 0;

				real += value * cosNow;
				imaginary += value * sinNow;

				final held = cosNow * cosStep - sinNow * sinStep;
				sinNow = cosNow * sinStep + sinNow * cosStep;
				cosNow = held;
			}

			final power = Math.sqrt(real * real + imaginary * imaginary) / many;
			bins[bin] = power;
			if (power > most) most = power;
		}

		return most;
	}

	/**
		@param part Which part.
		@param start Where the run starts in the lane.
		@param many How long it is.
		@return The largest sample in the run, ignoring its sign.
	**/
	function loudest(part:Int, start:Int, many:Int):Float {
		final base = part * SPAN;
		var most = 0.0;
		var at = start;

		for (step in 0...many) {
			final held = traces[base + at];
			final value = held < 0 ? -held : held;

			if (value > most) most = value;

			at++;
			if (at >= SPAN) at = 0;
		}

		return most;
	}

	/**
		Lays a window of samples out across a lane, into `line`.

		Where there are no more samples than columns, every sample is a point. Where there are
		more, each column is drawn as the highest and the lowest sample that falls in it, so a
		peak narrower than a pixel still shows rather than falling between two points.

		@param base Where the lane starts in the traces.
		@param start Where the window starts in the lane.
		@param many How many samples the window holds.
		@param columns How many pixels across the lane is.
		@param left Where the trace starts, across.
		@param across How wide it is.
		@param middle Where nought is, down.
		@param gain How far down one unit of sample goes.
		@return How many points were laid.
	**/
	function traced(base:Int, start:Int, many:Int, columns:Int, left:Float, across:Float,
			middle:Float, gain:Float):Int {
		if (many <= columns) {
			final step = many > 1 ? across / (many - 1) : across;
			var read = start;

			for (i in 0...many) {
				line[i * 2] = left + i * step;
				line[i * 2 + 1] = middle - traces[base + read] * gain;

				read++;
				if (read >= SPAN) read = 0;
			}

			return many;
		}

		final wide = columns > FIT ? FIT : columns;
		final step = across / wide;

		var read = start;
		var used = 0;

		for (column in 0...wide) {
			final until = Std.int((column + 1) * many / wide);

			var low = traces[base + read];
			var high = low;

			while (used < until) {
				final value = traces[base + read];

				if (value < low) low = value;
				if (value > high) high = value;

				read++;
				if (read >= SPAN) read = 0;

				used++;
			}

			line[column * 4] = left + column * step;
			line[column * 4 + 1] = middle - high * gain;
			line[column * 4 + 2] = left + (column + 0.5) * step;
			line[column * 4 + 3] = middle - low * gain;
		}

		return wide * 2;
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

		final reach = tall * 0.5 - inset * 2;
		final many = window();

		if (showing == SPECTRUM) {
			final analysed = many < ANALYSED ? many : ANALYSED;
			final start = (written[part] - analysed + SPAN) % SPAN;

			if (loudest(part, start, analysed) <= 0.0005) return;

			final most = bands(part, start, analysed);
			if (most <= 0) return;

			final step = across / BARS;
			final stalk = step * 0.62;
			final floor = middle + reach;

			for (bin in 0...BARS) {
				final share = bins[bin] / most;
				final high = reach * 2 * share;
				if (high < 1) continue;

				paint.rect(from + bin * step, floor - high, stalk, high, theme.part(part), 0.9);
			}

			painted++;
			return;
		}

		final start = startOf(part);
		final peak = loudest(part, start, many);

		if (peak <= 0.0005) return;

		paint.rect(from, middle, across, metrics.whole(1), theme.frame, 0.5);

		final columns = Std.int(across) < 2 ? 2 : Std.int(across);
		final count = traced(part * SPAN, start, many, columns, from, across, middle,
			reach / peak);

		painted++;
		paint.polyline(line, count, metrics.whole(1.5), theme.part(part), 0.95);

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
