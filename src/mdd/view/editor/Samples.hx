package mdd.view.editor;

import haxe.ds.Vector;
import mdd.app.Locale;
import mdd.app.Session;
import mdd.song.Sample;
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
final class Samples extends Widget {
	public static inline final COLUMNS = 512;

	public final session:Session;

	public var chosen(default, null):Int = 0;
	public var start:Int = 0;
	public var ends:Int = -1;

	public var painted(default, null):Int = 0;

	final drawn:Vector<Float> = new Vector<Float>(COLUMNS * 2);

	var grabbing:Int = -1;
	var hoverAt:Int = -1;

	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;
	}

	public function sample():Null<Sample> {
		return session.song.sampleAt(chosen);
	}

	public function head():Float {
		final root = root();
		return root == null ? 30 : root.metrics.whole(30);
	}

	public function slots():Float {
		final root = root();
		return root == null ? 26 : root.metrics.row;
	}

	public function slotAt(py:Float):Int {
		final at = Std.int((py - y - head()) / slots());
		return at < 0 || at >= session.song.samples.length ? -1 : at;
	}

	public function waveTall():Float {
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

	public var budget:Null<mdd.check.Budget> = null;
	var menu:Null<Menu> = null;

	static function kb(bytes:Int):Float {
		return Math.round(bytes / 1024 * 10) / 10;
	}

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
		final loud = menu.offer(new Choice(translate(Locale.SAMPLE_NORMALISE)));
		final drop = menu.offer(new Choice(translate(Locale.SAMPLE_CLEAR)));

		if (held == null) {
			loud.enabled = false;
			drop.enabled = false;
			loud.reason = translate(Locale.SAMPLE_EMPTY);
			drop.reason = loud.reason;
		} else {
			fires(loud, function():Void normalised(held));
			fires(drop, function():Void cleared(slot));
		}

		root.pop(menu, px, py, this);
	}

	function fires(choice:Choice, what:Void -> Void):Void {
		choice.onFire = function(from:Choice):Void what();
	}

	function normalised(held:Sample):Void {
		final bytes = held.bytes;
		var most = 0;

		for (index in 0...bytes.length) {
			final away = bytes[index] - 128;
			final much = away < 0 ? -away : away;
			if (much > most) most = much;
		}

		if (most <= 0 || most >= 127) return;

		final gain = 127 / most;

		for (index in 0...bytes.length) {
			final value = Math.round((bytes[index] - 128) * gain) + 128;
			bytes[index] = value < 0 ? 0 : (value > 255 ? 255 : value);
		}

		session.say(translate(Locale.SAMPLE_NORMALISE));
		session.changed();
		invalidate();
	}

	function cleared(slot:Int):Void {
		if (slot < 0 || slot >= session.song.samples.length) return;

		session.holds();
		session.song.samples.splice(slot, 1);
		session.frees();
		if (chosen >= session.song.samples.length) chosen = session.song.samples.length - 1;

		session.changed();
		invalidate();
	}

	public function held():Int {
		var total = 0;
		for (sample in session.song.samples) total += sample.length();
		return total;
	}

	public inline function atByte(index:Int, sample:Sample):Float {
		final many = sample.length();
		return many == 0 ? x : x + width * index / many;
	}

	public function byteAt(px:Float, sample:Sample):Int {
		final many = sample.length();
		if (many == 0) return 0;

		final at = Math.round((px - x) * many / width);
		return at < 0 ? 0 : (at >= many ? many - 1 : at);
	}

	override function took(event:Input):Bool {
		final sample = sample();

		switch (event.kind) {
			case Kind.PointerDown:
				final slot = slotAt(event.y);

				if (slot >= 0) {
					chosen = slot;
					start = 0;
					ends = -1;
					invalidate();

					if (event.button == Pointer.Right) popped(slot, event.x, event.y);
					return true;
				}

				if (sample == null || event.y < wave()) return false;

				final at = byteAt(event.x, sample);
				final near = Math.abs(at - start) < Math.abs(at - (ends < 0 ? sample.length() : ends));

				grabbing = near ? 0 : 1;
				if (near) start = at;
				else ends = at;

				invalidate();
				return true;

			case Kind.PointerMove:
				final slot = slotAt(event.y);

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

	public function trim():Void {
		final sample = sample();
		if (sample == null) return;

		final from = start < 0 ? 0 : start;
		final until = ends < 0 || ends > sample.length() ? sample.length() : ends;

		if (until <= from) return;

		final held = new Vector<Int>(until - from);
		for (i in 0...held.length) held[i] = sample.bytes[from + i];

		session.holds();
		sample.hold(held);
		session.frees();

		start = 0;
		ends = -1;

		session.changed();
		invalidate();
	}

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
		final total = held();
		final ceiling = budget == null ? 65536 : budget.profile.sampleBytes;
		final over = total > ceiling;

		paint.textRight(kb(total) + " / " + kb(ceiling) + " kb",
			x + width - metrics.inset, y + head() * 0.5 + small.ascent * 0.5,
			over ? theme.over : theme.dim, 0.8);

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
			paint.textRight(sample.length() + " at " + sample.rate + " Hz",
				x + width - metrics.inset, row + (tall - small.height) * 0.5 + small.ascent,
				theme.dim, 0.75);
		}

		paint.popClip();
		waveform(paint, theme, metrics);
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
