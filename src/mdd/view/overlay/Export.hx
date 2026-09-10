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
import mdd.ui.control.Number;

@:unreflective

/**
	The export sheet: the format, the rate, the depth, the padding, the fade, the
	normalising, the output stage and the metadata.

	It carries its own `Mixing` rather than reading the one in preferences, so choosing
	a different output stage for one export does not change what is monitored.
**/
final class Export extends Widget {
	/**
		Row: which format to write.
	**/
	public static inline final FORMAT = 0;

	/**
		Row: the sample rate.
	**/
	public static inline final RATE = 1;

	/**
		Row: bits per sample.
	**/
	public static inline final DEPTH = 2;

	/**
		Row: mono or stereo.
	**/
	public static inline final SIDES = 3;
	static inline final LEAD = 4;

	/**
		Row: how much silence after the piece.
	**/
	public static inline final TAIL = 5;
	static inline final FADE = 6;

	/**
		Row: where the loudest sample lands.
	**/
	public static inline final CEILING = 7;
	static inline final DITHER = 8;
	static inline final QUALITY = 9;
	static inline final CONSOLE = 10;
	static inline final OPUS_MODE = 11;
	static inline final OPUS_SPAN = 12;
	static inline final OPUS_BITRATE = 13;

	/**
		Row: whether one file per part is written beside the mix.
	**/
	public static inline final STEMS = 14;

	/**
		How many rows there are.
	**/
	public static inline final KINDS = 15;

	/**
		How many metadata fields there are.
	**/
	public static inline final FIELDS = 5;

	/**
		How many of the rows are times typed in seconds rather than chosen.
	**/
	public static inline final TIMED = 3;

	static final NAMES:Array<Locale> = [Locale.EXPORT_FORMAT, Locale.EXPORT_RATE,
		Locale.EXPORT_DEPTH, Locale.EXPORT_SIDES, Locale.EXPORT_LEAD, Locale.EXPORT_TAIL,
		Locale.EXPORT_FADE, Locale.EXPORT_CEILING, Locale.EXPORT_DITHER,
		Locale.EXPORT_QUALITY, Locale.EXPORT_CONSOLE, Locale.EXPORT_OPUS_MODE,
		Locale.EXPORT_OPUS_SPAN, Locale.EXPORT_OPUS_BITRATE, Locale.EXPORT_STEMS];

	static final TIMINGS:Array<Locale> = [Locale.EXPORT_LEAD, Locale.EXPORT_TAIL,
		Locale.EXPORT_FADE];

	static final LABELS:Array<Locale> = [Locale.EXPORT_TITLE, Locale.EXPORT_ARTIST,
		Locale.EXPORT_ALBUM, Locale.EXPORT_YEAR, Locale.EXPORT_COMMENT];

	static final FORMATS:Array<String> = ["WAV", "FLAC", "Ogg Vorbis", "Opus"];

	static final QUALITIES:Array<String> = ["q2", "q4", "q6", "q8", "q10"];
	static final KILOBITS:Array<String> = ["96k", "128k", "160k", "192k", "256k"];
	static final SIDINGS:Array<Locale> = [Locale.EXPORT_MONO, Locale.EXPORT_STEREO];
	static final SWITCHES:Array<Locale> = [Locale.EXPORT_OFF, Locale.EXPORT_ON];

	static final CONSOLES:Array<Locale> = [Locale.CONSOLE_CHIP, Locale.CONSOLE_ONE,
		Locale.CONSOLE_TWO];

	static final OPUS_MODES:Array<Locale> = [Locale.EXPORT_OPUS_LOCAL,
		Locale.EXPORT_OPUS_STREAM];

	static final OPUS_BITRATE_MODES:Array<Locale> = [Locale.EXPORT_OPUS_VBR,
		Locale.EXPORT_OPUS_BOUND, Locale.EXPORT_OPUS_FIXED];

	static final SPANS:Array<Int> = [5, 10, 20, 40, 60];

	static final SPANNED:Array<String> = ["5 ms", "10 ms", "20 ms", "40 ms", "60 ms"];

	static final NOTHING:Array<String> = [];
	static final NO_KEYS:Array<Locale> = [];
	static final ONE_RATE:Array<String> = ["48000"];

	static final SECONDS:Array<Float> = [0, 0.5, 1, 2];
	static final TAILS:Array<Float> = [0, 1, 2, 4];

	static final LEADS:Array<String> = ["0", "0.5 s", "1 s", "2 s"];
	static final TAILED:Array<String> = ["0", "1 s", "2 s", "4 s"];

	/**
		The session to read.
	**/
	public var session:Session;

	/**
		What this export is set to. It is this sheet's own copy.
	**/
	public final mixing:Mixing = new Mixing();

	var picked:Bool = false;

	/**
		The metadata fields.
	**/
	public final fields:Array<Field> = [];

	/**
		The typed times.
	**/
	public final timers:Array<Number> = [];

	/**
		The button that starts the export.
	**/
	public final go:Button;

	/**
		The button that closes the sheet.
	**/
	public final stop:Button;

	/**
		How far it has risen into place.
	**/
	public final rise:Motion;

	/**
		How far it has faded in.
	**/
	public final fade:Motion;

	/**
		Called with the settings when the export is started.
	**/
	public var onExport:Null<Mixing -> Void> = null;

	/**
		Called when the sheet closes.
	**/
	public var onShut:Null<Void -> Void> = null;

	var hoverAt:Int = -1;
	var hoverOn:Int = -1;

	final showing:Array<Int> = [];

	/**
		Builds the sheet and every field on it.

		@param session The session to read.
	**/
	public function new(session:Session) {
		super();
		modal = true;
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

		for (index in 0...TIMED) {
			final held = new Number("", 0, 0, 200);

			held.derived = function(value:Int):String return spelt(value);
			held.onChange = function(from:Number):Void timed(index, from.value);

			timers.push(held);
			add(held);
		}

		go = new Button("");
		stop = new Button("");

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
		showing.push(CEILING);
		showing.push(CONSOLE);

		if (mixing.kind == Mixing.OPUS) {
			showing.push(OPUS_MODE);
			showing.push(OPUS_SPAN);
			showing.push(OPUS_BITRATE);
		}

		if (mixing.whole() && mixing.depth < 32) showing.push(DITHER);

		showing.push(STEMS);
	}

	/**
		@return How many rows are shown, which depends on the format: bit depth and dither mean
			nothing to a format that does not carry whole samples.
	**/
	public function rows():Int {
		if (showing.length == 0) ordered();
		return showing.length;
	}

	/**
		Shows the sheet and reads the settings into it.
	**/
	public function ask():Void {
		ordered();

		if (mixing.title == "") mixing.title = session.song.name;
		if (mixing.artist == "") mixing.artist = session.song.author;

		fields[0].set(mixing.title);
		fields[1].set(mixing.artist);
		fields[2].set(mixing.album);
		fields[3].set(mixing.year);
		fields[4].set(mixing.comment);

		fills();

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

	/**
		@return How tall one row is.
	**/
	public function rowTall():Float {
		final root = root();
		return root == null ? 42 : root.metrics.whole(42);
	}

	/**
		@return How tall a metadata field is.
	**/
	public function fieldTall():Float {
		final root = root();
		return root == null ? 40 : root.metrics.whole(40);
	}

	/**
		@return How tall the title band is.
	**/
	public function head():Float {
		final root = root();
		return root == null ? 46 : root.metrics.whole(46);
	}

	override function measure(availableWidth:Float, availableHeight:Float):Void {
		final root = root();
		final metrics = root == null ? null : root.metrics;

		wantWidth = metrics == null ? 640 : metrics.whole(640);
		wantHeight = metrics == null ? 620 : head() + rows() * rowTall()
			+ metrics.whole(24) + (FIELDS + TIMED) * fieldTall() + metrics.control
			+ metrics.inset * 3;
	}

	override function layout():Void {
		final root = root();
		if (root == null) return;

		final metrics = root.metrics;
		final small = metrics.small == null ? metrics.body : metrics.small;
		final label = small == null ? 12 : small.height;

		var top = y + head() + rows() * rowTall() + metrics.whole(24);

		for (index in 0...TIMED) {
			timers[index].arrange(x + metrics.whole(120), top + label * 0.2,
				metrics.whole(120), fieldTall() - metrics.gap * 2);

			top += fieldTall();
		}

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

	/**
		@param row Which row.
		@return What each choice on it is called.
	**/
	public function labels(row:Int):Array<Locale> {
		return switch (row) {
			case SIDES: SIDINGS;
			case CONSOLE: CONSOLES;
			case OPUS_MODE: OPUS_MODES;
			case OPUS_BITRATE: OPUS_BITRATE_MODES;
			case FORMAT, RATE, DEPTH, LEAD, TAIL, FADE, QUALITY, OPUS_SPAN: NO_KEYS;
			case _: SWITCHES;
		}
	}

	/**
		@param row Which row.
		@return The choices on it that are not translated, such as the rates.
	**/
	public function choices(row:Int):Array<String> {
		return switch (row) {
			case FORMAT: FORMATS;
			case RATE: mixing.kind == Mixing.OPUS ? ONE_RATE : rates();
			case DEPTH: depths();
			case LEAD: LEADS;
			case TAIL, FADE: TAILED;

			case QUALITY: mixing.kind == Mixing.OPUS ? KILOBITS : QUALITIES;
			case OPUS_SPAN: SPANNED;
			case _: NOTHING;
		}
	}

	/**
		@param row Which row.
		@return How many choices it offers.
	**/
	public function counted(row:Int):Int {
		final keys = labels(row);
		return keys.length > 0 ? keys.length : choices(row).length;
	}

	static function rates():Array<String> {
		final held:Array<String> = [];
		for (rate in Mixing.RATES) held.push("" + rate);

		return held;
	}

	static function depths():Array<String> {
		return ["16", "24", "32"];
	}

	/**
		@param row Which row.
		@return Which choice is taken.
	**/
	public function holding(row:Int):Int {
		return switch (row) {
			case FORMAT: mixing.kind;
			case RATE: mixing.kind == Mixing.OPUS ? 0 : nearest(Mixing.RATES, mixing.rate);
			case DEPTH: mixing.depth == 32 ? 2 : (mixing.depth == 24 ? 1 : 0);
			case SIDES: mixing.stereo ? 1 : 0;
			case LEAD: closest(SECONDS, mixing.padStart);
			case TAIL: closest(TAILS, mixing.padEnd);
			case FADE: closest(TAILS, mixing.fade);
			case CEILING: mixing.normalise ? 1 : 0;
			case CONSOLE: mixing.console;
			case OPUS_MODE: mixing.opusMode;
			case OPUS_BITRATE: mixing.opusBitrateMode;
			case OPUS_SPAN: spanAt();
			case QUALITY: mixing.quality;
			case STEMS: mixing.stems ? 1 : 0;
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

	/**
		Takes the output stage the preferences are set to, for a sheet that has not
		been given one of its own yet.

		@param which Which output stage.
	**/
	public function follows(which:Int):Void {
		if (!picked) mixing.console = which;
	}

	/**
		Takes a choice on a row, and hides the rows it makes meaningless.

		@param row Which row.
		@param which Which choice.
	**/
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
				mixing.ceiling = 0;

			case CONSOLE: { mixing.console = which; picked = true; }
			case OPUS_MODE: mixing.opusMode = which;
			case OPUS_BITRATE: mixing.opusBitrateMode = which;
			case OPUS_SPAN: mixing.opusSpan = SPANS[which];

			case QUALITY: mixing.quality = which;
			case STEMS: mixing.stems = which == 1;
			case _: mixing.dither = which == 1;
		}

		if (mixing.kind == Mixing.FLAC && mixing.depth == 32) mixing.depth = 24;
		if (mixing.kind == Mixing.OPUS) mixing.rate = mdd.format.Coded.OPUS_RATE;

		ordered();

		session.changed();
		relayout();
	}

	/**
		@param py A point, down.
		@return Which row is there, or -1.
	**/
	public function rowAt(py:Float):Int {
		final at = Std.int((py - y - head()) / rowTall());
		if (at < 0 || at >= rows()) return -1;

		return showing[at];
	}

	function optionAt(row:Int, px:Float):Int {
		final root = root();
		if (root == null) return -1;

		final many = counted(row);
		if (many <= 0) return -1;

		final metrics = root.metrics;
		final wide = (width - metrics.whole(120) - metrics.inset) / many;

		final at = Std.int((px - x - metrics.whole(120)) / wide);
		return at < 0 || at >= many ? -1 : at;
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

	function spanAt():Int {
		for (index in 0...SPANS.length) if (SPANS[index] == mixing.opusSpan) return index;
		return 2;
	}

	static function spelt(value:Int):String {
		return value == 0 ? "0" : (Math.round(value * 5) / 100) + " s";
	}

	function timed(which:Int, value:Int):Void {
		final held = value / 20.0;

		switch (which) {
			case 0: mixing.padStart = held;
			case 1: mixing.padEnd = held;
			case _: mixing.fade = held;
		}

		session.changed();
		invalidate();
	}

	function fills():Void {
		if (timers.length < TIMED) return;

		timers[0].set(Math.round(mixing.padStart * 20));
		timers[1].set(Math.round(mixing.padEnd * 20));
		timers[2].set(Math.round(mixing.fade * 20));
	}

	function shown(row:Int, which:Int):String {
		final keys = labels(row);

		if (keys.length > 0) {
			return which < 0 || which >= keys.length ? "" : translate(keys[which]);
		}

		final held = choices(row);
		return which < 0 || which >= held.length ? "" : held[which];
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

			final many = counted(row);
			if (many <= 0) continue;

			final wide = room / many;
			final on = holding(row);
			final button = tall - metrics.gap * 2;
			final at = top + metrics.gap;

			for (which in 0...many) {
				final where = left + which * wide;

				paint.roundedRect(where + 1, at, wide - 2, button, metrics.radiusSmall,
					which == on ? theme.accent : theme.raise2,
					(which == on ? 0.85 : 1) * alpha);

				if (row == hoverAt && which == hoverOn && which != on) {
					paint.roundedRect(where + 1, at, wide - 2, button, metrics.radiusSmall,
						theme.accent, Theme.HOVER * alpha);
				}

				paint.pushClip(where + 1, at, wide - 2, button);
				paint.textCentred(shown(row, which), where + wide * 0.5,
					at + (button - small.height) * 0.5 + small.ascent,
					which == on ? theme.ink : theme.dim, alpha);
				paint.popClip();
			}
		}

		var top = y + head() + rows() * tall + metrics.whole(24);

		paint.reface(small);

		for (index in 0...TIMED) {
			paint.text(translate(TIMINGS[index]), x + metrics.inset,
				top + (fieldTall() - small.height) * 0.5 + small.ascent, theme.dim,
				alpha * 0.9);

			top += fieldTall();
		}

		for (index in 0...FIELDS) {
			paint.text(translate(LABELS[index]), x + metrics.inset,
				top + (fieldTall() - small.height) * 0.5 + small.ascent, theme.dim,
				alpha * 0.9);

			top += fieldTall();
		}

		for (held in timers) held.paint(paint);
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
			+ (mixing.whole() ? "   " + mixing.depth + " bit" : "")
			+ (mixing.rate < 44100 ? "   " + translate(Locale.EXPORT_COARSE) : "");
	}
}
