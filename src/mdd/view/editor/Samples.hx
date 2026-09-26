package mdd.view.editor;

import haxe.ds.Vector;
import mdd.app.Locale;
import mdd.app.Session;
import mdd.song.Sample;
import mdd.song.edit.LoudenSample;
import mdd.song.edit.RemoveSample;
import mdd.song.edit.TrimSample;
import mdd.ui.Input;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Panel;
import mdd.ui.Pointer;
import mdd.ui.control.Choice;
import mdd.ui.control.Menu;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective

/**
	The sample editor: the waveform, where it starts and ends, and the slots of the
	kit it belongs to.
**/
final class Samples extends Widget {
	/**
		How many columns the waveform is reduced to, whatever it holds.
	**/
	public static inline final COLUMNS = 512;

	/**
		The session to read.
	**/
	public final session:Session;

	/**
		Which slot of the kit is chosen.
	**/
	public var chosen(default, null):Int = 0;

	/**
		Where the sample starts, in bytes.
	**/
	public var start:Int = 0;

	/**
		Where it ends, or -1 for the whole of it.
	**/
	public var ends:Int = -1;

	/**
		How many columns the last frame drew.
	**/
	public var painted(default, null):Int = 0;

	final drawn:Vector<Float> = new Vector<Float>(COLUMNS * 2);

	var grabbing:Int = -1;
	var hoverAt:Int = -1;

	var totalShown:Int = -1;
	var ceilingShown:Int = -1;
	var totalText:String = "";
	final rowLength:Array<Int> = [];
	final rowRate:Array<Int> = [];
	final rowText:Array<String> = [];

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
		@return The chosen sample, or null where the slot is empty.
	**/
	public function sample():Null<Sample> {
		return session.song.sampleAt(chosen);
	}

	/**
		@return How tall the header is.
	**/
	public function head():Float {
		final root = root();
		return root == null ? 26 : root.metrics.head;
	}

	/**
		@return How tall the slot list is.
	**/
	public function slots():Float {
		final root = root();
		return root == null ? 26 : root.metrics.row;
	}

	/**
		@param py A point, down.
		@return Which slot is there, or -1.
	**/
	public function slotAt(py:Float):Int {
		final at = Std.int((py - y - head()) / slots());
		return at < 0 || at >= session.song.samples.length ? -1 : at;
	}

	function waveTall():Float {
		final root = root();
		if (root == null) return 200;

		final most = root.metrics.whole(200);
		final room = height - head() - slots();

		return room < most ? (room < 0 ? 0 : room) : most;
	}

	function wave():Float {
		final listed = y + head() + session.song.samples.length * slots();
		final floor = y + height - waveTall();

		return listed < floor ? listed : floor;
	}

	/**
		What says how much sample room the machine has, so the bar can show what is left.
	**/
	public var budget:Null<mdd.check.Budget> = null;
	var menu:Null<Menu> = null;

	static function kb(bytes:Int):Float {
		return Math.round(bytes / 1024 * 10) / 10;
	}

	/**
		Called to import a wave file into the chosen slot.
	**/
	public var onImport:Null<Void -> Void> = null;

	function popped(slot:Int, px:Float, py:Float):Void {
		final root = root();
		if (root == null) return;

		menu = new Menu();

		fires(menu.offer(new Choice(translate(Locale.FILE_READ_WAV))), function():Void {
			if (onImport != null) onImport();
		});

		menu.divide();

		final held = session.song.samples[slot];
		final cut = menu.offer(new Choice(translate(Locale.SAMPLE_TRIM)));
		final loud = menu.offer(new Choice(translate(Locale.SAMPLE_NORMALISE)));
		final drop = menu.offer(new Choice(translate(Locale.SAMPLE_CLEAR)));

		if (held == null) {
			cut.enabled = false;
			loud.enabled = false;
			drop.enabled = false;
			loud.reason = translate(Locale.SAMPLE_EMPTY);
			cut.reason = loud.reason;
			drop.reason = loud.reason;
		} else {
			if (slot == chosen && trims()) {
				fires(cut, function():Void trim());
			} else {
				cut.enabled = false;
				cut.reason = translate(Locale.SAMPLE_TRIM_NONE);
			}

			fires(loud, function():Void normalised(slot));
			fires(drop, function():Void cleared(slot));
		}

		root.pop(menu, px, py, this);
	}

	/**
		Scales a recording up to full scale, as one undoable step.

		@param slot Which recording, by index.
	**/
	function normalised(slot:Int):Void {
		final held = session.song.sampleAt(slot);
		if (held == null || !LoudenSample.worth(held)) return;

		session.does(new LoudenSample(slot));
		session.say(translate(Locale.SAMPLE_NORMALISE));
		invalidate();
	}

	/**
		Takes a recording out, as one undoable step. Every instrument that named one
		after it moves with it.

		@param slot Which recording, by index.
	**/
	function cleared(slot:Int):Void {
		if (slot < 0 || slot >= session.song.samples.length) return;

		session.does(new RemoveSample(slot));

		if (chosen >= session.song.samples.length) chosen = session.song.samples.length - 1;
		invalidate();
	}

	/**
		@return How many bytes every recording in the piece adds up to, which is what the
			panel weighs against what the machine has room for.
	**/
	public function taken():Int {
		var total = 0;
		for (sample in session.song.samples) total += sample.length();
		return total;
	}

	inline function atByte(index:Int, sample:Sample):Float {
		final many = sample.length();
		return many == 0 ? x : x + width * index / many;
	}

	/**
		@param px A point, across the waveform.
		@param sample The recording drawn there.
		@return The byte boundary nearest the point, from nought to the recording's length, so an
			end marker can be put past the last byte.
	**/
	function byteAt(px:Float, sample:Sample):Int {
		final many = sample.length();
		if (many == 0) return 0;

		final at = Math.round((px - x) * many / width);
		return at < 0 ? 0 : (at > many ? many : at);
	}

	override function took(event:Input):Bool {
		final sample = sample();

		switch (event.kind) {
			case Kind.PointerDown:
				final slot = slotAt(event.y);

				if (slot >= 0) {
					if (slot != chosen) {
						chosen = slot;
						start = 0;
						ends = -1;
					}

					invalidate();

					if (event.button == Pointer.Right) popped(slot, event.x, event.y);
					return true;
				}

				if (sample == null || event.y < wave()) return false;

				if (event.button == Pointer.Right) {
					popped(chosen, event.x, event.y);
					return true;
				}

				final at = byteAt(event.x, sample);
				final near = Math.abs(at - start) < Math.abs(at - (ends < 0 ? sample.length() : ends));

				grabbing = near ? 0 : 1;
				if (near) start = at;
				else ends = at;

				invalidate();
				return true;

			case Kind.PointerMove:
				final slot = slotAt(event.y);

				final over = slot < 0 && sample != null && event.y >= wave();

				tip = slot >= 0 ? session.song.samples[slot].name
					: (over ? translate(Locale.SAMPLE_WAVE_TIP) : "");
				detail = slot >= 0 ? translate(Locale.TIP_MORE)
					: (over ? translate(Locale.SAMPLE_WAVE_DETAIL) : "");

				if (slot != hoverAt) {
					hoverAt = slot;
					invalidate();
				}

				if (grabbing < 0 || sample == null) return grabbing >= 0;

				final at = byteAt(event.x, sample);
				if (grabbing == 0) start = at;
				else ends = at;

				invalidate();
				return true;

			case Kind.PointerUp:
				if (grabbing < 0) return false;

				grabbing = -1;
				session.changed();
				return true;

			case _:
		}

		return false;
	}

	/**
		Cuts the chosen recording down to what lies between the two markers, whichever way round
		they were dragged, as one undoable step, and puts the markers back around all of what is
		left. The loop point moves with the sound, as `TrimSample` says.
	**/
	public function trim():Void {
		final sample = sample();
		if (sample == null || !trims()) return;

		session.does(new TrimSample(chosen, kept(sample, true), kept(sample, false)));

		start = 0;
		ends = -1;

		session.say(translate(Locale.SAMPLE_TRIM));
		invalidate();
	}

	/**
		@return Whether the markers leave out any of the chosen recording, so trimming to them
			would change it.
	**/
	public function trims():Bool {
		final sample = sample();
		return sample != null && TrimSample.worth(sample, kept(sample, true), kept(sample, false));
	}

	/**
		@param sample The chosen recording.
		@param first Whether to answer where what is kept starts rather than where it ends.
		@return The first byte the markers keep, or one past the last, whichever way round the
			markers are.
	**/
	function kept(sample:Sample, first:Bool):Int {
		final many = sample.length();
		final one = start < 0 ? 0 : (start > many ? many : start);
		final two = ends < 0 || ends > many ? many : ends;

		return first ? (one < two ? one : two) : (one < two ? two : one);
	}

	/**
		Scales the sample so its loudest byte reaches full.
	**/
	public function normalise():Void {
		final sample = sample();
		if (sample == null || sample.length() == 0) return;

		var most = 0;

		for (i in 0...sample.length()) {
			final off = sample.bytes[i] - 128;
			final size = off < 0 ? -off : off;
			if (size > most) most = size;
		}

		if (most == 0 || most >= 127) return;

		final held = new Vector<Int>(sample.length());

		for (i in 0...held.length) {
			final value = Math.round((sample.bytes[i] - 128) * 127 / most) + 128;
			held[i] = value < 0 ? 0 : (value > 255 ? 255 : value);
		}

		session.holds();
		sample.hold(held);
		session.frees();

		session.changed();
		invalidate();
	}

	override function hovered(on:Bool):Void {
		if (!on) hoverAt = -1;
		super.hovered(on);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final small = metrics.small == null ? metrics.body : metrics.small;

		paint.rect(x, y, width, height, theme.panel);
		painted = 0;

		paint.reface(small);
		Panel.titled(paint, theme, metrics, translate(Locale.PANEL_SAMPLES), x, y, width,
			head());
		paint.reface(small);
		final total = taken();
		final ceiling = budget == null ? 65536 : budget.profile.sampleBytes;
		final over = total > ceiling;

		if (total != totalShown || ceiling != ceilingShown) {
			totalShown = total;
			ceilingShown = ceiling;
			totalText = kb(total) + " / " + kb(ceiling) + " kb";
		}

		paint.textRight(totalText, x + width - metrics.inset,
			y + head() * 0.5 + small.ascent * 0.5, over ? theme.over : theme.dim, 0.8);

		final tall = slots();

		final floor = wave();

		paint.pushClip(x, y + head(), width, floor - y - head());

		for (index in 0...session.song.samples.length) {
			final row = y + head() + index * tall;
			if (row > floor) break;

			if (index == chosen) {
				paint.rect(x, row, width, tall, theme.accent, Theme.SELECT);
			} else if (index == hoverAt) {
				paint.rect(x, row, width, tall, theme.accent, Theme.HOVER);
			}

			final sample = session.song.samples[index];

			paint.text(sample.name, x + metrics.inset,
				row + (tall - small.height) * 0.5 + small.ascent, theme.ink);
			paint.textRight(sized(index, sample), x + width - metrics.inset,
				row + (tall - small.height) * 0.5 + small.ascent, theme.dim, 0.75);
		}

		paint.popClip();
		waveform(paint, theme, metrics);
	}

	/**
		@param index A row.
		@param sample The recording on it.
		@return How long the recording is and the rate it plays at, made again only when either
			has changed, so a frame of rows allocates nothing.
	**/
	function sized(index:Int, sample:Sample):String {
		while (rowText.length <= index) {
			rowLength.push(-1);
			rowRate.push(-1);
			rowText.push("");
		}

		final length = sample.length();

		if (length != rowLength[index] || sample.rate != rowRate[index]) {
			rowLength[index] = length;
			rowRate[index] = sample.rate;
			rowText[index] = length + " at " + sample.rate + " Hz";
		}

		return rowText[index];
	}

	function waveform(paint:Paint, theme:Theme, metrics:Metrics):Void {

		final sample = sample();
		final top = wave();
		final tall = waveTall();

		if (tall < metrics.row) return;

		paint.rect(x, top, width, tall, theme.sink, 0.6);

		if (sample == null || sample.length() == 0) return;

		final middle = top + tall * 0.5;
		final many = sample.length();
		final columns = COLUMNS > Std.int(width) ? Std.int(width) : COLUMNS;

		if (columns < 2) return;

		for (column in 0...columns) {
			final from = Std.int(column * many / columns);
			var until = Std.int((column + 1) * many / columns);
			if (until <= from) until = from + 1;
			if (until > many) until = many;

			var peak = 0;

			for (i in from...until) {
				final off = sample.bytes[i] - 128;
				final size = off < 0 ? -off : off;
				if (size > peak) peak = size;
			}

			final high = tall * 0.5 * peak / 128;
			final at = x + width * column / columns;

			paint.rect(at, middle - high, width / columns, high * 2, theme.part(10), 0.85);
		}

		painted = columns;

		paint.rect(x, middle, width, metrics.whole(1), theme.frame, 0.6);

		final from = atByte(start, sample);
		final until = atByte(ends < 0 ? many : ends, sample);

		paint.rect(from, top, metrics.whole(2), tall, theme.accent, 0.9);
		paint.rect(until - metrics.whole(2), top, metrics.whole(2), tall, theme.accent, 0.9);

		if (sample.loop >= 0) {
			paint.rect(atByte(sample.loop, sample), top, metrics.whole(1), tall, theme.warn, 0.8);
		}
	}
}
