package mdd.view;

import mdd.app.Locale;
import mdd.app.Session;
import mdd.song.Song;
import mdd.song.Tempo;
import mdd.song.edit.SetTempo;
import mdd.ui.Input;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;
import mdd.ui.control.Choice;
import mdd.ui.control.Menu;
import mdd.ui.control.Number;

@:unreflective
final class TransportBar extends Widget {
	public static inline final PLAY = 0;
	public static inline final STOP = 1;
	public static inline final RECORD = 2;
	public static inline final REWIND = 3;
	public static inline final LOOP = 4;
	public static inline final BUTTONS = 5;

	static final SNAPS:Array<Int> = [16, 8, 4, 2, 1];
	static final SNAP_NAMES:Array<String> = ["1/16", "1/8", "1/4", "1/2", "1/1"];

	static final TIPS:Array<Locale> = [Locale.TRANSPORT_PLAY, Locale.TRANSPORT_STOP,
		Locale.TRANSPORT_RECORD, Locale.TRANSPORT_REWIND, Locale.TRANSPORT_LOOP];
	static final CHORDS:Array<String> = ["Space", "Ctrl+Space", "R", "Home", "Ctrl+L"];

	public final session:Session;

	public final tempo:Number;
	public final offset:Number;
	public var regrids:Bool = false;
	public final resolution:Number;
	public final length:Number;
	public final video:Number;
	public final snap:Number;

	final held:Array<Number>;

	public var onMaster:Null<Int -> Void> = null;

	var hoverAt:Int = -1;
	var overMode:Int = -1;
	var overPicker:Bool = false;
	var overVolume:Bool = false;
	var sliding:Bool = false;
	var menu:Null<Menu> = null;
	var settling:Bool = false;

	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;

		final song = session.song;

		tempo = new Number("", Math.round(song.tempo.beatsAt(0)), 20, 400);
		resolution = new Number("", song.tempo.ppqn, 24, 48000);
		length = new Number("", bars(), 1, 256);
		video = new Number("", song.tempo.rate == 50 ? 0 : 1, 0, 1);
		snap = new Number("", snapIndex(), 0, SNAPS.length - 1);
		offset = new Number("", song.offset, -960, 960);

		held = [tempo, resolution, length, video, snap, offset];

		video.derived = function(value:Int):String return (value == 0 ? "50" : "60") + " Hz";
		snap.derived = function(value:Int):String return SNAP_NAMES[value];

		tempo.label = "BPM";
		resolution.label = "PPQN";
		video.label = "";
		snap.label = "";
		offset.label = "SHIFT";

		for (field in held) add(field);

		tempo.onChange = function(from:Number):Void tempoChanged(from);
		resolution.onChange = function(from:Number):Void resolutionChanged(from);
		length.onChange = function(from:Number):Void lengthChanged(from);
		video.onChange = function(from:Number):Void videoChanged(from);
		snap.onChange = function(from:Number):Void snapChanged(from);
		offset.onChange = function(from:Number):Void offsetChanged(from);
	}

	public function fields():Array<Number> {
		return held;
	}

	function bars():Int {
		final pattern = session.current();
		final bar = session.song.tempo.ppqn * 4;

		return pattern == null || bar <= 0 ? 4 : Math.round(pattern.length / bar);
	}

	function snapIndex():Int {
		final ppqn = session.song.tempo.ppqn;

		for (index in 0...SNAPS.length) {
			if (Math.round(ppqn * 4 / SNAPS[index]) == session.snap) return index;
		}

		return 0;
	}

	public function settles():Void {
		if (settling) return;
		settling = true;

		final pattern = session.current();
		final named = pattern == null ? translate(Locale.TRANSPORT_BARS) : pattern.name;

		if (named != length.label) {
			length.label = named;
			relayout();
		}

		tempo.set(Math.round(session.song.tempo.beatsAt(0)));
		offset.set(session.song.offset);
		resolution.set(session.song.tempo.ppqn);
		length.set(bars());
		video.set(session.song.tempo.rate == 50 ? 0 : 1);
		snap.set(snapIndex());

		settling = false;
	}

	function tempoChanged(from:Number):Void {
		if (settling) return;
		if (regrids) session.does(new mdd.song.edit.SetGrid(from.value));
		else session.does(new SetTempo(0, from.value));
	}

	function offsetChanged(from:Number):Void {
		if (settling) return;

		final by = from.value - session.song.offset;
		if (by == 0) return;

		session.does(new mdd.song.edit.ShiftSong(by));
	}

	function resolutionChanged(from:Number):Void {
		if (settling) return;

		session.song.retick(from.value);
		session.snap = Math.round(from.value * 4 / SNAPS[snap.value]);
		session.changed();
	}

	function lengthChanged(from:Number):Void {
		if (settling) return;

		final pattern = session.current();
		if (pattern == null) return;

		session.does(new mdd.song.edit.ResizePattern(session.pattern,
			from.value * session.song.tempo.ppqn * 4));
	}

	function videoChanged(from:Number):Void {
		if (settling) return;

		session.song.tempo.rate = from.value == 0 ? 50 : 60;
		session.changed();
	}

	function snapChanged(from:Number):Void {
		if (settling) return;

		session.snap = Math.round(session.song.tempo.ppqn * 4 / SNAPS[from.value]);
		session.changed();
	}

	function described(which:Int):Void {
		if (which < 0) {
			tip = "";
			chord = "";
			detail = "";
			return;
		}

		final root = root();
		final key = which == PLAY && session.transport.playing
			? Locale.TRANSPORT_PAUSE : TIPS[which];

		tip = root == null ? "" : translate(key);
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

	function modeLeft():Float {
		final root = root();
		if (root == null) return x;

		final metrics = root.metrics;
		return x + metrics.inset + (size() + metrics.unit) * BUTTONS + metrics.inset;
	}

	function modeWide():Float {
		final root = root();
		return root == null ? 44 : root.metrics.whole(44);
	}

	public function modeAt(px:Float, py:Float):Int {
		final root = root();
		if (root == null) return -1;

		final button = size();
		final top = y + (height - button) * 0.5;

		if (py < top || py >= top + button) return -1;

		final left = modeLeft();
		final wide = modeWide();

		if (px < left || px >= left + wide * 2) return -1;
		return px < left + wide ? 0 : 1;
	}

	function pickerLeft():Float {
		final root = root();
		if (root == null) return x;

		return modeLeft() + modeWide() * 2 + root.metrics.inset;
	}

	function pickerWide():Float {
		final root = root();
		return root == null ? 150 : root.metrics.whole(150);
	}

	public var peak(default, null):Float = 0;

	public function metered(much:Float):Void {
		if (Math.abs(much - peak) < 0.01) return;

		peak = much;
		invalidate();
	}

	function volumeLeft():Float {
		final root = root();
		return root == null ? x : clockRight() + root.metrics.inset;
	}

	function volumeWide():Float {
		final root = root();
		return root == null ? 132 : root.metrics.whole(132);
	}

	function speakerWide():Float {
		final root = root();
		return root == null ? 16 : root.metrics.whole(16);
	}

	function trackLeft():Float {
		final root = root();
		return volumeLeft() + speakerWide() + (root == null ? 8 : root.metrics.gap);
	}

	function trackWide():Float {
		return volumeLeft() + volumeWide() - trackLeft();
	}

	public function onVolume(px:Float, py:Float):Bool {
		final button = size();
		final top = y + (height - button) * 0.5;

		return px >= volumeLeft() && px < volumeLeft() + volumeWide()
			&& py >= top && py < top + button;
	}

	function leaned(px:Float):Void {
		final room = trackWide();
		if (room <= 0) return;

		var part = (px - trackLeft()) / room;
		if (part < 0) part = 0;
		if (part > 1) part = 1;

		final want = Math.round(part * Song.LOUDEST);
		if (session.master == want) return;

		session.master = want;
		if (onMaster != null) onMaster(want);

		session.say(translate(Locale.TRANSPORT_VOLUME) + "  "
			+ Math.round(want * 100 / Song.LOUDEST) + "%");

		invalidate();
	}

	public function onPicker(px:Float, py:Float):Bool {
		final button = size();
		final top = y + (height - button) * 0.5;

		if (py < top || py >= top + button) return false;

		final left = pickerLeft();
		return px >= left && px < left + pickerWide();
	}

	override function took(event:Input):Bool {
		if (super.took(event)) return true;

		switch (event.kind) {
			case Kind.PointerDown:
				final which = buttonAt(event.x, event.y);

				if (which >= 0) {
					press(which);
					invalidate();
					return true;
				}

				final mode = modeAt(event.x, event.y);

				if (mode >= 0) {
					session.plays(mode == 0);
					invalidate();
					return true;
				}

				if (onPicker(event.x, event.y)) {
					popped(pickerLeft(), y + height);
					return true;
				}

				if (onVolume(event.x, event.y)) {
					sliding = true;
					leaned(event.x);
					return true;
				}

			case Kind.PointerMove:
				if (sliding) {
					leaned(event.x);
					return true;
				}

				final which = buttonAt(event.x, event.y);
				final mode = modeAt(event.x, event.y);
				final picker = onPicker(event.x, event.y);
				final volume = onVolume(event.x, event.y);

				described(which);

				if (which == hoverAt && mode == overMode && picker == overPicker
					&& volume == overVolume) return false;

				hoverAt = which;
				overMode = mode;
				overPicker = picker;
				overVolume = volume;
				invalidate();
				return true;

			case Kind.PointerUp:
				if (!sliding) return false;

				sliding = false;
				return true;

			case Kind.Wheel:
				if (!onVolume(event.x, event.y)) return false;

				leaned(trackLeft() + trackWide() * session.master / Song.LOUDEST
					+ event.dy * trackWide() / 20);

				return true;

			case _:
		}

		return false;
	}

	public var onPatterns:Null<Int -> Void> = null;

	public static inline final ADD = 0;
	public static inline final DUPLICATE = 1;
	public static inline final RENAME = 2;
	public static inline final DELETE = 3;

	function popped(px:Float, py:Float):Void {
		final root = root();
		if (root == null) return;

		menu = new Menu();

		for (index in 0...session.song.patterns.length) {
			final which = index;
			final pattern = session.song.patterns[index];

			final choice = menu.offer(new Choice((index + 1) + "  " + pattern.name,
				pattern.notes() == 0 ? "" : "" + pattern.notes()));

			choice.onFire = function(from:Choice):Void session.chooses(which);
		}

		menu.divide();

		commands(menu, Locale.PATTERN_ADD, ADD);
		commands(menu, Locale.PATTERN_DUPLICATE, DUPLICATE);
		commands(menu, Locale.PATTERN_RENAME, RENAME);

		final drop = commands(menu, Locale.PATTERN_DELETE, DELETE);

		if (session.song.patterns.length <= 1) {
			drop.enabled = false;
			drop.reason = translate(Locale.PATTERN_LAST);
		}

		root.pop(menu, px, py, this);
	}

	function commands(into:Menu, key:Locale, which:Int):Choice {
		final choice = into.offer(new Choice(translate(key)));

		choice.onFire = function(from:Choice):Void
			if (onPatterns != null) onPatterns(which);

		return choice;
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

			case RECORD:
				session.arming = !session.arming;
				session.say(translate(session.arming
					? Locale.TRANSPORT_ARMED : Locale.TRANSPORT_DISARMED));

			case REWIND:
				transport.seek(0);

			case LOOP:
				transport.looping = !transport.looping;
				session.say(translate(transport.looping
					? Locale.TRANSPORT_LOOPING : Locale.TRANSPORT_ONCE));

			case _:
		}

		session.changed();
	}

	override function hovered(on:Bool):Void {
		if (!on) {
			hoverAt = -1;
			overMode = -1;
			overPicker = false;
			overVolume = false;
		}

		super.hovered(on);
	}

	override function layout():Void {
		final root = root();
		if (root == null) return;

		settles();

		final metrics = root.metrics;
		final button = size();
		final top = y + (height - button) * 0.5;

		final after = volumeLeft() + volumeWide() + metrics.inset;
		final room = x + width - metrics.inset - after;

		var many = held.length;
		var shown = 0.0;

		while (many > 0) {
			shown = 0;
			for (index in 0...many) shown += held[index].fits() + metrics.unit;

			if (shown - metrics.unit <= room) break;
			many--;
		}

		shown = shown < metrics.unit ? 0 : shown - metrics.unit;

		var pen = x + width - metrics.inset - shown;

		for (index in 0...held.length) {
			final field = held[index];

			field.visible = index < many;
			if (!field.visible) continue;

			final wide = field.fits();

			field.arrange(pen, top, wide, button);
			pen += wide + metrics.unit;
		}
	}

	function clockRight():Float {
		final root = root();
		if (root == null) return x;

		final metrics = root.metrics;
		final font = metrics.mono == null ? metrics.body : metrics.mono;

		return pickerLeft() + pickerWide() + metrics.inset + font.measure("00:00.000")
			+ metrics.inset + font.measure("bar 000.0");
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		settles();

		final theme = root.theme;
		final metrics = root.metrics;
		final button = size();
		final top = y + (height - button) * 0.5;
		final transport = session.transport;

		paint.rect(x, y, width, height, theme.bar);

		var pen = x + metrics.inset;

		for (index in 0...BUTTONS) {
			final on = switch (index) {
				case PLAY: transport.playing;
				case RECORD: session.arming;
				case LOOP: transport.looping;
				case _: false;
			}

			final lit = index == RECORD ? theme.over : theme.accent;

			if (on) {
				paint.roundedGradient(pen, top, button, button, metrics.radiusRow,
					lit.lift(0.20), lit.sink(0.16), 0.92);
			} else {
				paint.roundedRect(pen, top, button, button, metrics.radiusRow,
					theme.raise2);
			}

			if (index == hoverAt) {
				paint.roundedRect(pen, top, button, button, metrics.radiusRow, theme.accent,
					Theme.HOVER);
			}

			glyph(paint, theme, metrics, index, pen, top, button, on);
			pen += button + metrics.unit;
		}

		mode(paint, theme, metrics, top, button);
		picker(paint, theme, metrics, top, button);
		volume(paint, theme, metrics, top, button);

		final font = metrics.mono == null ? metrics.body : metrics.mono;

		paint.reface(font);

		final line = y + (height - font.height) * 0.5 + font.ascent;
		final clockAt = pickerLeft() + pickerWide() + metrics.inset;
		final barAt = clockAt + font.measure("00:00.000") + metrics.inset;
		final room = barAt + font.measure("bar 000.0") - clockAt + metrics.inset;

		paint.roundedRect(clockAt - metrics.gap, top, room, button, metrics.radiusRow,
			theme.sink);

		paint.text(clock(transport.seconds()), clockAt, line, theme.ink);
		paint.text(bar(transport.tick()), barAt, line, theme.dim, 0.9);

		for (field in held) if (field.visible) field.paint(paint);
	}

	function mode(paint:Paint, theme:Theme, metrics:Metrics, top:Float, button:Float):Void {
		final left = modeLeft();
		final wide = modeWide();
		final font = metrics.small == null ? metrics.body : metrics.small;
		final line = top + (button - font.height) * 0.5 + font.ascent;
		final on = session.alone ? 0 : 1;

		paint.reface(font);
		paint.roundedRect(left, top, wide * 2, button, metrics.radiusRow, theme.raise2);
		paint.outline(left, top, wide * 2, button, theme.frame, metrics.whole(1), 1,
			metrics.radiusRow);
		paint.roundedGradient(left + wide * on, top, wide, button, metrics.radiusRow,
			theme.accent.lift(0.20), theme.accent.sink(0.16), 0.85);

		if (overMode >= 0) {
			paint.roundedRect(left + wide * overMode, top, wide, button, metrics.radiusRow,
				theme.accent, Theme.HOVER);
		}

		paint.textCentred(translate(Locale.TRANSPORT_PATTERN), left + wide * 0.5, line,
			on == 0 ? theme.ink : theme.dim, 0.75);
		paint.textCentred(translate(Locale.TRANSPORT_SONG), left + wide * 1.5, line,
			on == 1 ? theme.ink : theme.dim, 0.75);
	}

	function volume(paint:Paint, theme:Theme, metrics:Metrics, top:Float, button:Float):Void {
		final middle = top + button * 0.5;

		speaker(paint, theme, metrics, volumeLeft(), middle, speakerWide());

		final left = trackLeft();
		final room = trackWide();
		if (room <= 0) return;

		final track = metrics.whole(6);
		final line = middle - track * 0.5;
		final want = session.master / Song.LOUDEST;

		paint.roundedRect(left, line, room, track, track * 0.5, theme.sink);

		if (peak > 0.004) {
			paint.roundedGradient(left, line, room, track, track * 0.5,
				theme.accent.lift(0.24), theme.accent.sink(0.2), 0.5,
				peak > 1 ? 1 : peak);
		}

		paint.roundedRect(left, line, room, track, track * 0.5, theme.ink, 0.55, want);

		final grip = metrics.whole(12);
		final at = left + room * want;

		paint.roundedRect(at - grip * 0.5, middle - grip * 0.5, grip, grip, grip * 0.5,
			theme.ink, sliding || overVolume ? 1 : 0.85);
	}

	function speaker(paint:Paint, theme:Theme, metrics:Metrics, at:Float, middle:Float,
			size:Float):Void {
		final ink = overVolume || sliding ? theme.ink : theme.dim;
		final reach = size * 0.5;
		final quiet = session.master <= 0;

		paint.rect(at, middle - reach * 0.35, reach * 0.5, reach * 0.7, ink);

		final points = new haxe.ds.Vector<Float>(6);

		points[0] = at + reach * 0.85;
		points[1] = middle - reach * 0.85;
		points[2] = at + reach * 0.85;
		points[3] = middle + reach * 0.85;
		points[4] = at;
		points[5] = middle;

		paint.polygon(points, 3, ink);

		if (quiet) {
			paint.line(at + reach, middle - reach * 0.7, at + size, middle + reach * 0.7,
				metrics.whole(2), theme.over);

			return;
		}

		final weight = metrics.whole(2);
		final much = session.master / Song.LOUDEST;

		paint.arc(at + reach * 0.7, middle, reach * 0.7, -0.9, 0.9, weight, ink, 0.9);

		if (much > 0.55) {
			paint.arc(at + reach * 0.7, middle, reach * 1.15, -0.8, 0.8, weight, ink, 0.7);
		}
	}

	function picker(paint:Paint, theme:Theme, metrics:Metrics, top:Float, button:Float):Void {
		final left = pickerLeft();
		final wide = pickerWide();
		final font = metrics.body;
		final line = top + (button - font.height) * 0.5 + font.ascent;
		final pattern = session.current();

		paint.roundedRect(left, top, wide, button, metrics.radiusRow, theme.raise2);

		if (overPicker) {
			paint.roundedRect(left, top, wide, button, metrics.radiusRow, theme.accent,
				Theme.HOVER);
		}

		final swatch = metrics.whole(10);

		paint.roundedRect(left + metrics.gap, top + (button - swatch) * 0.5, swatch, swatch,
			metrics.radiusSmall, Theme.PARTS[session.pattern % Theme.PARTS.length]);

		final arrow = metrics.whole(4);
		final textAt = left + metrics.gap * 2 + swatch;
		final room = wide - (textAt - left) - arrow * 2 - metrics.gap * 2;

		paint.reface(font);
		paint.pushClip(textAt, top, room, button);
		paint.text((session.pattern + 1) + "  " + (pattern == null ? "" : pattern.name),
			textAt, line, theme.ink, 0.85);
		paint.popClip();

		final middle = left + wide - metrics.gap - arrow;
		final centre = top + button * 0.5;
		final points = new haxe.ds.Vector<Float>(6);

		points[0] = middle - arrow;
		points[1] = centre - arrow * 0.5;
		points[2] = middle + arrow;
		points[3] = centre - arrow * 0.5;
		points[4] = middle;
		points[5] = centre + arrow * 0.6;

		paint.polygon(points, 3, theme.dim);
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

			case RECORD:
				paint.circle(middle, centre, reach * 0.8, on ? theme.ink : theme.over);

			case REWIND:
				paint.rect(middle - reach * 0.9, centre - reach * 0.8, metrics.whole(2),
					reach * 1.6, ink);

				final points = new haxe.ds.Vector<Float>(6);
				points[0] = middle + reach * 0.8;
				points[1] = centre - reach * 0.8;
				points[2] = middle + reach * 0.8;
				points[3] = centre + reach * 0.8;
				points[4] = middle - reach * 0.4;
				points[5] = centre;
				paint.polygon(points, 3, ink);

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

	public function bar(tick:Int):String {
		final beat = session.song.tempo.ppqn;
		final span = beat * 4;
		final which = Std.int(tick / span) + 1;
		final within = Std.int((tick % span) / beat) + 1;

		return "bar " + which + "." + within;
	}
}
