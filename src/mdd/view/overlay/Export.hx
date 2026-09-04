package mdd.view.overlay;

import mdd.app.Locale;
import mdd.app.Session;
import mdd.play.Mixing;
import mdd.ui.Input;
import mdd.ui.Key;
import mdd.ui.Kind;
import mdd.ui.Motion;
import mdd.ui.Paint;
import mdd.ui.Theme;
import mdd.ui.Widget;
import mdd.ui.control.Button;
import mdd.ui.control.Field;

@:unreflective
final class Export extends Widget {
	public static inline final FORMAT = 0;
	public static inline final RATE = 1;
	public static inline final DEPTH = 2;
	public static inline final SIDES = 3;
	public static inline final LEAD = 4;
	public static inline final TAIL = 5;
	public static inline final FADE = 6;
	public static inline final CEILING = 7;
	public static inline final DITHER = 8;
	public static inline final QUALITY = 9;
	public static inline final KINDS = 10;

	public static inline final FIELDS = 5;

	static final NAMES:Array<String> = [Locale.EXPORT_FORMAT, Locale.EXPORT_RATE,
		Locale.EXPORT_DEPTH, Locale.EXPORT_SIDES, Locale.EXPORT_LEAD, Locale.EXPORT_TAIL,
		Locale.EXPORT_FADE, Locale.EXPORT_CEILING, Locale.EXPORT_DITHER,
		Locale.EXPORT_QUALITY];

	static final LABELS:Array<String> = [Locale.EXPORT_TITLE, Locale.EXPORT_ARTIST,
		Locale.EXPORT_ALBUM, Locale.EXPORT_YEAR, Locale.EXPORT_COMMENT];

	static final FORMATS:Array<String> = ["WAV", "FLAC", "Ogg Vorbis", "Opus"];

	static final QUALITIES:Array<String> = ["q2", "q4", "q6", "q8", "q10"];
	static final RATED:Array<String> = ["96k", "128k", "160k", "192k", "256k"];
	static final SIDINGS:Array<String> = [Locale.EXPORT_MONO, Locale.EXPORT_STEREO];
	static final SWITCHES:Array<String> = [Locale.EXPORT_OFF, Locale.EXPORT_ON];

	static final SECONDS:Array<Float> = [0, 0.5, 1, 2];
	static final TAILS:Array<Float> = [0, 1, 2, 4];
	static final CEILINGS:Array<Float> = [0, -0.1, -0.3, -1, -3];

	static final LEADS:Array<String> = ["0", "0.5 s", "1 s", "2 s"];
	static final TAILED:Array<String> = ["0", "1 s", "2 s", "4 s"];
	static final CEILED:Array<String> = [Locale.EXPORT_OFF, "-0.1 dB", "-0.3 dB", "-1 dB",
		"-3 dB"];

	public var session:Session;
	public final mixing:Mixing = new Mixing();

	public final fields:Array<Field> = [];
	public final go:Button;
	public final stop:Button;

	public final rise:Motion;
	public final fade:Motion;

	public var onExport:Null<Mixing -> Void> = null;
	public var onShut:Null<Void -> Void> = null;

	var hoverAt:Int = -1;
	var hoverOn:Int = -1;

	final showing:Array<Int> = [];

	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;

		rise = new Motion(this, 0, true);
		fade = new Motion(this, 0, false);

		for (index in 0...FIELDS) {
			final held = new Field("");

			held.onChange = function(said:String):Void kept();
			fields.push(held);
			add(held);
		}

		go = new Button(Locale.EXPORT_GO);
		stop = new Button(Locale.EXPORT_CANCEL);

		add(go);
		add(stop);

		go.onFire = function(button:Button):Void fired();
		stop.onFire = function(button:Button):Void shut();
	}

	function ordered():Void {
		showing.resize(0);

		showing.push(FORMAT);
		showing.push(RATE);

		if (mixing.whole()) showing.push(DEPTH);
		else showing.push(QUALITY);

		showing.push(SIDES);
		showing.push(LEAD);
		showing.push(TAIL);
		showing.push(FADE);
		showing.push(CEILING);

		if (mixing.whole() && mixing.depth < 32) showing.push(DITHER);
	}

	public function rows():Int {
		if (showing.length == 0) ordered();
		return showing.length;
	}

	public function ask():Void {
		ordered();

		if (mixing.title == "") mixing.title = session.song.name;
		if (mixing.artist == "") mixing.artist = session.song.author;

		fields[0].set(mixing.title);
		fields[1].set(mixing.artist);
		fields[2].set(mixing.album);
		fields[3].set(mixing.year);
		fields[4].set(mixing.comment);

		final root = root();
		if (root == null) return;

		rise.hold(0);
		fade.hold(0);

		root.start(rise, 1, Motion.ENTER);
		root.start(fade, 1, Motion.ENTER);
	}

	function kept():Void {
		mixing.title = fields[0].value;
		mixing.artist = fields[1].value;
		mixing.album = fields[2].value;
		mixing.year = fields[3].value;
		mixing.comment = fields[4].value;
	}

	function fired():Void {
		kept();

		final what = onExport;
		if (what != null) what(mixing);

		shut();
	}

	function shut():Void {
		if (onShut != null) onShut();
	}

	public function rowTall():Float {
		final root = root();
		return root == null ? 42 : root.metrics.whole(42);
	}

	public function fieldTall():Float {
		final root = root();
		return root == null ? 40 : root.metrics.whole(40);
	}

	public function head():Float {
		final root = root();
		return root == null ? 46 : root.metrics.whole(46);
	}

	override function measure(availableWidth:Float, availableHeight:Float):Void {
		final root = root();
		final metrics = root == null ? null : root.metrics;

		wantWidth = metrics == null ? 640 : metrics.whole(640);
		wantHeight = metrics == null ? 620 : head() + rows() * rowTall()
			+ metrics.whole(24) + FIELDS * fieldTall() + metrics.control
			+ metrics.inset * 3;
	}

	override function layout():Void {
		final root = root();
		if (root == null) return;

		final metrics = root.metrics;
		final small = metrics.small == null ? metrics.body : metrics.small;
		final label = small == null ? 12 : small.height;

		var top = y + head() + rows() * rowTall() + metrics.whole(24);

		for (index in 0...FIELDS) {
			fields[index].arrange(x + metrics.whole(120), top + label * 0.2,
				width - metrics.whole(120) - metrics.inset, fieldTall() - metrics.gap * 2);

			top += fieldTall();
		}

		final wide = metrics.whole(120);
		final bottom = y + height - metrics.inset - metrics.control;

		stop.arrange(x + width - metrics.inset - wide * 2 - metrics.gap, bottom, wide,
			metrics.control);
		go.arrange(x + width - metrics.inset - wide, bottom, wide, metrics.control);
	}

	public function choices(row:Int):Array<String> {
		return switch (row) {
			case FORMAT: FORMATS;
			case RATE: mixing.kind == Mixing.OPUS ? ["48000"] : rates();
			case DEPTH: depths();
			case SIDES: SIDINGS;
			case LEAD: LEADS;
			case TAIL: TAILED;
			case FADE: TAILED;
			case CEILING: CEILED;
			case QUALITY: mixing.kind == Mixing.OPUS ? RATED : QUALITIES;
			case _: SWITCHES;
		}
	}

	static function rates():Array<String> {
		final held:Array<String> = [];
		for (rate in Mixing.RATES) held.push("" + rate);

		return held;
	}

	static function depths():Array<String> {
		return ["16", "24", "32"];
	}

	public function holding(row:Int):Int {
		return switch (row) {
			case FORMAT: mixing.kind;
			case RATE: mixing.kind == Mixing.OPUS ? 0 : nearest(Mixing.RATES, mixing.rate);
			case DEPTH: mixing.depth == 32 ? 2 : (mixing.depth == 24 ? 1 : 0);
			case SIDES: mixing.stereo ? 1 : 0;
			case LEAD: closest(SECONDS, mixing.padStart);
			case TAIL: closest(TAILS, mixing.padEnd);
			case FADE: closest(TAILS, mixing.fade);
			case CEILING: mixing.normalise ? closest(CEILINGS, mixing.ceiling) : 0;
			case QUALITY: mixing.quality;
			case _: mixing.dither ? 1 : 0;
		}
	}

	static function nearest(held:Array<Int>, want:Int):Int {
		for (index in 0...held.length) if (held[index] == want) return index;
		return 0;
	}

	static function closest(held:Array<Float>, want:Float):Int {
		var best = 0;
		var least = -1.0;

		for (index in 0...held.length) {
			final away = held[index] - want;
			final much = away < 0 ? -away : away;

			if (least >= 0 && much >= least) continue;

			best = index;
			least = much;
		}

		return best;
	}

	public function chose(row:Int, which:Int):Void {
		switch (row) {
			case FORMAT: mixing.kind = which;
			case RATE: mixing.rate = mixing.kind == Mixing.OPUS
				? mdd.format.Coded.OPUS_RATE : Mixing.RATES[which];
			case DEPTH: mixing.depth = which == 2 ? 32 : (which == 1 ? 24 : 16);
			case SIDES: mixing.stereo = which == 1;
			case LEAD: mixing.padStart = SECONDS[which];
			case TAIL: mixing.padEnd = TAILS[which];
			case FADE: mixing.fade = TAILS[which];

			case CEILING:
				mixing.normalise = which > 0;
				if (which > 0) mixing.ceiling = CEILINGS[which];

			case QUALITY: mixing.quality = which;
			case _: mixing.dither = which == 1;
		}

		if (mixing.kind == Mixing.FLAC && mixing.depth == 32) mixing.depth = 24;
		if (mixing.kind == Mixing.OPUS) mixing.rate = mdd.format.Coded.OPUS_RATE;

		ordered();

		session.changed();
		relayout();
	}

	public function rowAt(py:Float):Int {
		final at = Std.int((py - y - head()) / rowTall());
		if (at < 0 || at >= rows()) return -1;

		return showing[at];
	}

	public function optionAt(row:Int, px:Float):Int {
		final root = root();
		if (root == null) return -1;

		final held = choices(row);
		final metrics = root.metrics;
		final wide = (width - metrics.whole(120) - metrics.inset) / held.length;

		final at = Std.int((px - x - metrics.whole(120)) / wide);
		return at < 0 || at >= held.length ? -1 : at;
	}

	override function took(event:Input):Bool {
		if (super.took(event)) return true;

		switch (event.kind) {
			case Kind.KeyDown:
				if (event.code != Key.Escape) return false;

				shut();
				return true;

			case Kind.PointerDown:
				final row = rowAt(event.y);
				if (row < 0) return true;

				final which = optionAt(row, event.x);
				if (which < 0) return true;

				chose(row, which);
				return true;

			case Kind.PointerMove:
				final row = rowAt(event.y);
				final which = row < 0 ? -1 : optionAt(row, event.x);

				if (row == hoverAt && which == hoverOn) return true;

				hoverAt = row;
				hoverOn = which;
				invalidate();
				return true;

			case _:
		}

		return true;
	}

	override function hovered(on:Bool):Void {
		if (!on) {
			hoverAt = -1;
			hoverOn = -1;
		}

		super.hovered(on);
	}

	function shown(row:Int, which:Int, label:String):String {
		if (row == RATE || row == LEAD || row == TAIL || row == FADE) return label;
		if (row == FORMAT || row == DEPTH || row == QUALITY) return label;
		if (row == CEILING && which > 0) return label;

		return translate(label);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final alpha = fade.value;

		if (alpha <= 0.004) return;

		final lift = (1 - rise.value) * metrics.sizeOf(8);
		paint.pushTransform(0, lift);

		paint.roundedRect(x, y, width, height, metrics.radiusPanel, theme.raise1, alpha);
		paint.outline(x, y, width, height, theme.frame, metrics.whole(1), alpha,
			metrics.radiusPanel);

		final font = metrics.body;
		final small = metrics.small == null ? font : metrics.small;

		paint.reface(font);
		paint.text(translate(Locale.EXPORT), x + metrics.inset,
			y + metrics.inset + font.ascent, theme.ink, alpha);

		paint.reface(small);
		paint.textRight(said(), x + width - metrics.inset,
			y + metrics.inset + small.ascent, theme.dim, alpha * 0.8);

		final tall = rowTall();
		final left = x + metrics.whole(120);
		final room = width - metrics.whole(120) - metrics.inset;

		for (index in 0...rows()) {
			final row = showing[index];
			final top = y + head() + index * tall;

			paint.reface(small);
			paint.text(translate(NAMES[row]), x + metrics.inset,
				top + (tall - small.height) * 0.5 + small.ascent, theme.dim, alpha * 0.9);

			final held = choices(row);
			final wide = room / held.length;
			final on = holding(row);
			final button = tall - metrics.gap * 2;
			final at = top + metrics.gap;

			for (which in 0...held.length) {
				final where = left + which * wide;

				paint.roundedRect(where + 1, at, wide - 2, button, metrics.radiusSmall,
					which == on ? theme.accent : theme.raise2,
					(which == on ? 0.85 : 1) * alpha);

				if (row == hoverAt && which == hoverOn && which != on) {
					paint.roundedRect(where + 1, at, wide - 2, button, metrics.radiusSmall,
						theme.accent, Theme.HOVER * alpha);
				}

				paint.pushClip(where + 1, at, wide - 2, button);
				paint.textCentred(shown(row, which, held[which]), where + wide * 0.5,
					at + (button - small.height) * 0.5 + small.ascent,
					which == on ? theme.ink : theme.dim, alpha);
				paint.popClip();
			}
		}

		var top = y + head() + rows() * tall + metrics.whole(24);

		for (index in 0...FIELDS) {
			paint.reface(small);
			paint.text(translate(LABELS[index]), x + metrics.inset,
				top + (fieldTall() - small.height) * 0.5 + small.ascent, theme.dim,
				alpha * 0.9);

			top += fieldTall();
		}

		for (held in fields) held.paint(paint);

		go.label = translate(Locale.EXPORT_GO);
		stop.label = translate(Locale.EXPORT_CANCEL);

		stop.paint(paint);
		go.paint(paint);

		paint.popTransform();
	}

	function said():String {
		final song = session.song;
		final seconds = song.tempo.samplesAt(song.ends()) / mdd.song.Tempo.TICKS
			+ mixing.padStart + mixing.padEnd;

		return Math.round(seconds * 10) / 10 + " s   " + mixing.named() + "   "
			+ mixing.rate + " Hz   " + (mixing.stereo ? "2" : "1") + " ch"
			+ (mixing.whole() ? "   " + mixing.depth + " bit" : "");
	}
}
