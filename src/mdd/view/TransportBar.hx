package mdd.view;

import mdd.song.Tempo;
import mdd.ui.Input;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective
final class TransportBar extends Widget {
	public static inline final PLAY = 0;
	public static inline final STOP = 1;
	public static inline final LOOP = 2;
	public static inline final BUTTONS = 3;

	public final session:Session;

	var hoverAt:Int = -1;

	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;
	}

	static final TIPS:Array<String> = ["Play", "Stop and rewind", "Loop the pattern"];
	static final CHORDS:Array<String> = ["Space", "Ctrl+Space", "Ctrl+L"];

	function described(which:Int):Void {
		if (which < 0) {
			tip = "";
			chord = "";
			detail = "";
			return;
		}

		tip = which == PLAY && session.transport.playing ? "Pause" : TIPS[which];
		chord = CHORDS[which];
		detail = "";
	}

	function size():Float {
		final root = root();
		return root == null ? 30 : root.metrics.whole(30);
	}

	public function buttonAt(px:Float, py:Float):Int {
		final root = root();
		if (root == null) return -1;

		final metrics = root.metrics;
		final button = size();
		final top = y + (height - button) * 0.5;

		if (py < top || py >= top + button) return -1;

		var pen = x + metrics.inset;

		for (index in 0...BUTTONS) {
			if (px >= pen && px < pen + button) return index;
			pen += button + metrics.unit;
		}

		return -1;
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				final which = buttonAt(event.x, event.y);
				if (which < 0) return false;

				press(which);
				invalidate();
				return true;

			case Kind.PointerMove:
				final which = buttonAt(event.x, event.y);
				described(which);

				if (which == hoverAt) return false;

				hoverAt = which;
				invalidate();
				return true;

			case _:
		}

		return false;
	}

	public function press(which:Int):Void {
		final transport = session.transport;

		switch (which) {
			case PLAY:
				if (transport.playing) transport.stop();
				else transport.play();

			case STOP:
				transport.stop();
				transport.seek(0);

			case LOOP:
				if (transport.looping) transport.looping = false;
				else {
					final pattern = session.current();
					final length = pattern == null ? 384 : pattern.length;
					transport.loop(0, session.song.tempo.samplesAt(length));
				}

			case _:
		}

		session.changed();
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
		final button = size();
		final top = y + (height - button) * 0.5;
		final transport = session.transport;

		paint.rect(x, y, width, height, theme.bar);

		var pen = x + metrics.inset;

		for (index in 0...BUTTONS) {
			final on = index == PLAY ? transport.playing
				: (index == LOOP ? transport.looping : false);

			paint.roundedRect(pen, top, button, button, metrics.radiusRow,
				on ? theme.accent : theme.raise1, on ? 0.85 : 1);

			if (index == hoverAt) {
				paint.roundedRect(pen, top, button, button, metrics.radiusRow, theme.accent,
					Theme.HOVER);
			}

			glyph(paint, theme, metrics, index, pen, top, button, on);
			pen += button + metrics.unit;
		}

		final font = metrics.mono == null ? metrics.body : metrics.mono;
		final small = metrics.small == null ? metrics.body : metrics.small;

		paint.reface(font);

		final line = y + (height - font.height) * 0.5 + font.ascent;
		pen += metrics.inset;

		paint.text(clock(transport.seconds()), pen, line, theme.ink);
		pen += font.measure("00:00.000") + metrics.inset;

		paint.text(bars(transport.tick()), pen, line, theme.ink);
		pen += font.measure("bar 000.0") + metrics.inset;

		paint.reface(small);

		final beats = session.song.tempo.beatsAt(transport.tick());
		final said = Std.string(Math.round(beats * 10) / 10) + " BPM   "
			+ session.song.tempo.ppqn + " PPQN   " + session.song.tempo.rate + " Hz";

		paint.textRight(said, x + width - metrics.inset,
			y + (height - small.height) * 0.5 + small.ascent, theme.dim);
	}

	function glyph(paint:Paint, theme:Theme, metrics:Metrics, which:Int, at:Float, top:Float,
			size:Float, on:Bool):Void {
		final ink = on ? theme.ink : theme.dim;
		final middle = at + size * 0.5;
		final centre = top + size * 0.5;
		final reach = metrics.whole(6);

		switch (which) {
			case PLAY:
				if (session.transport.playing) {
					paint.rect(middle - reach * 0.7, centre - reach, reach * 0.5, reach * 2, ink);
					paint.rect(middle + reach * 0.2, centre - reach, reach * 0.5, reach * 2, ink);
				} else {
					final points = new haxe.ds.Vector<Float>(6);
					points[0] = middle - reach * 0.6;
					points[1] = centre - reach;
					points[2] = middle + reach * 0.8;
					points[3] = centre;
					points[4] = middle - reach * 0.6;
					points[5] = centre + reach;
					paint.polygon(points, 3, ink);
				}

			case STOP:
				paint.rect(middle - reach * 0.8, centre - reach * 0.8, reach * 1.6, reach * 1.6,
					ink);

			case LOOP:
				paint.ring(middle, centre, reach * 0.8, metrics.whole(2), ink);

			case _:
		}
	}

	public static function clock(seconds:Float):String {
		final whole = Std.int(seconds);
		final minutes = Std.int(whole / 60);
		final rest = whole % 60;
		final parts = Std.int((seconds - whole) * 1000);

		return StringTools.lpad(Std.string(minutes), "0", 2) + ":"
			+ StringTools.lpad(Std.string(rest), "0", 2) + "."
			+ StringTools.lpad(Std.string(parts), "0", 3);
	}

	public function bars(tick:Int):String {
		final beat = session.song.tempo.ppqn;
		final bar = beat * 4;
		final which = Std.int(tick / bar) + 1;
		final within = Std.int((tick % bar) / beat) + 1;

		return "bar " + which + "." + within;
	}
}
