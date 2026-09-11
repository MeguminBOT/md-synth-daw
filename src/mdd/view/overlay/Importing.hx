package mdd.view.overlay;

import mdd.app.Locale;
import mdd.format.Strand;
import mdd.song.Part;
import mdd.ui.Input;
import mdd.ui.Kind;
import mdd.ui.Motion;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;
import mdd.ui.control.Button;

@:unreflective

/**
	The import sheet: what a MIDI file holds, and which of it to take.

	A file is surveyed rather than read, so nothing has happened to the piece by the
	time this is on screen and closing it leaves everything as it was. Every strand the
	file writes is a row: whether to take it, what the file called it, how much is in
	it, and which part it plays.

	Where it lands is the other choice. A file read as a new piece replaces what is
	open, which is what importing has always done and is what you want when the file is
	the piece. A file read into the piece becomes one more track, which is what you want
	when it is a part of one.
**/
final class Importing extends Widget {
	/**
		Where the import lands: as a track in the piece that is open.
	**/
	public static inline final INTO = 0;

	/**
		Where the import lands: as a piece of its own, replacing what is open.
	**/
	public static inline final INSTEAD = 1;

	/**
		How many rows are shown before it scrolls.
	**/
	static inline final SHOWN = 10;

	static final WHERE:Array<Locale> = [Locale.IMPORT_INTO, Locale.IMPORT_INSTEAD];

	/**
		What the file holds. Empty until `ask` is called.
	**/
	public var strands:Array<Strand> = [];

	/**
		What the file is called, for the title.
	**/
	public var called:String = "";

	/**
		Where the import lands, `INTO` or `INSTEAD`.
	**/
	public var lands:Int = INTO;

	/**
		The button that starts the import.
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
		Called with what to take when the import is started.
	**/
	public var onImport:Null<Array<Strand> -> Void> = null;

	/**
		Called when the sheet closes without importing.
	**/
	public var onShut:Null<Void -> Void> = null;

	var offset:Int = 0;
	var hoverAt:Int = -1;

	/**
		Builds the sheet with nothing in it.
	**/
	public function new() {
		super();

		modal = true;
		focusable = true;
		opaque = true;

		rise = new Motion(this, 0, true);
		fade = new Motion(this, 0, false);

		go = new Button("");
		stop = new Button("");

		add(go);
		add(stop);

		go.onFire = function(button:Button):Void fired();
		stop.onFire = function(button:Button):Void shut();
	}

	/**
		Shows the sheet for a file that has been surveyed.

		@param called What the file is called.
		@param strands What the survey found.
	**/
	public function ask(called:String, strands:Array<Strand>):Void {
		this.called = called;
		this.strands = strands;

		offset = 0;
		hoverAt = -1;

		go.label = translate(Locale.IMPORT_TAKE);
		stop.label = translate(Locale.EXPORT_CANCEL);

		final root = root();
		if (root == null) return;

		rise.hold(0);
		fade.hold(0);

		root.start(rise, 1, Motion.ENTER);
		root.start(fade, 1, Motion.ENTER);
	}

	/**
		@return How many strands are taken, which is what the button acts on.
	**/
	public function taking():Int {
		var many = 0;
		for (strand in strands) if (strand.taken) many++;

		return many;
	}

	/**
		Takes what was chosen. The sheet goes first and the import happens after, so
		nothing raised while the file is being read is lowered again by this closing.
	**/
	function fired():Void {
		if (taking() == 0) return;

		final what = onImport;
		final held = strands;

		shut();
		if (what != null) what(held);
	}

	function shut():Void {
		if (onShut != null) onShut();
	}

	/**
		@return How many rows are on screen at once.
	**/
	public function shown():Int {
		return strands.length < SHOWN ? strands.length : SHOWN;
	}

	/**
		@return How tall one strand is.
	**/
	public function rowTall():Float {
		final root = root();
		return root == null ? 30 : root.metrics.whole(30);
	}

	/**
		@return How tall the title band is.
	**/
	public function head():Float {
		final root = root();
		return root == null ? 46 : root.metrics.whole(46);
	}

	/**
		@return How tall the row that says where it lands is.
	**/
	public function bandTall():Float {
		final root = root();
		return root == null ? 42 : root.metrics.whole(42);
	}

	override function measure(availableWidth:Float, availableHeight:Float):Void {
		final root = root();
		final metrics = root == null ? null : root.metrics;

		wantWidth = metrics == null ? 640 : metrics.whole(640);
		wantHeight = metrics == null ? 480
			: head() + bandTall() + shown() * rowTall() + metrics.whole(24)
			+ metrics.control + metrics.inset * 2;
	}

	override function layout():Void {
		final root = root();
		if (root == null) return;

		final metrics = root.metrics;
		final wide = metrics.whole(120);
		final bottom = y + height - metrics.inset - metrics.control;

		stop.arrange(x + width - metrics.inset - wide * 2 - metrics.gap, bottom, wide,
			metrics.control);
		go.arrange(x + width - metrics.inset - wide, bottom, wide, metrics.control);
	}

	/**
		@return Where the list of strands starts, down the sheet.
	**/
	function listTop():Float {
		return y + head() + bandTall();
	}

	/**
		@param py A point, down.
		@return Which strand is there, or -1 where none is.
	**/
	function rowAt(py:Float):Int {
		final top = listTop();
		if (py < top) return -1;

		final at = offset + Std.int((py - top) / rowTall());
		return at >= 0 && at < strands.length && py < top + shown() * rowTall() ? at : -1;
	}

	/**
		How wide the part chooser is.
	**/
	public static inline final CHOOSER = 96;

	/**
		Everything left of this in a row turns the row on and off, so the whole line is
		the tick rather than the small box drawn as one.

		@param metrics What to measure with.
		@return Where the part chooser starts, across.
	**/
	public function chooserAt(metrics:mdd.ui.Metrics):Float {
		return x + width - metrics.inset - metrics.whole(CHOOSER);
	}

	override function took(event:Input):Bool {
		final root = root();
		if (root == null) return false;

		final metrics = root.metrics;

		switch (event.kind) {
			case Kind.Wheel:
				final most = strands.length - shown();
				if (most <= 0) return false;

				offset -= Std.int(event.dy);
				if (offset < 0) offset = 0;
				if (offset > most) offset = most;

				invalidate();
				return true;

			case Kind.PointerMove:
				final at = rowAt(event.y);
				if (at == hoverAt) return false;

				hoverAt = at;
				invalidate();
				return true;

			case Kind.PointerDown:
				if (event.button != Pointer.Left) return false;

				final band = y + head();

				if (event.y >= band && event.y < band + bandTall()) {
					final wide = (width - metrics.inset * 2) / WHERE.length;
					final which = Std.int((event.x - x - metrics.inset) / wide);

					if (which >= 0 && which < WHERE.length) {
						lands = which;
						invalidate();
					}

					return true;
				}

				final at = rowAt(event.y);
				if (at < 0) return true;

				final strand = strands[at];
				final chooser = chooserAt(metrics);

				if (event.x >= chooser) {
					final half = chooser + metrics.whole(CHOOSER) * 0.5;
					final by = event.x < half ? -1 : 1;

					strand.part = (strand.part + by + Part.COUNT) % Part.COUNT;
				} else {
					strand.taken = !strand.taken;
				}

				invalidate();
				return true;

			case Kind.KeyDown:
				if (event.code == mdd.ui.Key.Escape) {
					shut();
					return true;
				}

				return false;

			case _:
		}

		return false;
	}

	override function hovered(on:Bool):Void {
		if (on) return;

		hoverAt = -1;
		invalidate();
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
		paint.text(translate(Locale.IMPORT), x + metrics.inset,
			y + metrics.inset + font.ascent, theme.ink, alpha);

		paint.reface(small);
		paint.textRight(called, x + width - metrics.inset,
			y + metrics.inset + small.ascent, theme.dim, alpha * 0.8);

		banded(paint, theme, metrics, small, alpha);
		listed(paint, theme, metrics, small, alpha);

		paint.reface(small);
		paint.text(filled(Locale.IMPORT_TAKING, ["" + taking(), "" + strands.length]),
			x + metrics.inset, y + height - metrics.inset - metrics.control
			+ small.ascent + metrics.gap, theme.dim, alpha * 0.8);

		for (child in children) {
			if (child.visible) child.paint(paint);
		}

		paint.popTransform();
	}

	/**
		Draws the row that says where the import lands.

		@param paint What to draw with.
		@param theme The colours.
		@param metrics The measurements.
		@param small The face to write in.
		@param alpha How far the sheet has faded in.
	**/
	function banded(paint:Paint, theme:Theme, metrics:mdd.ui.Metrics, small:mdd.ui.Font,
			alpha:Float):Void {
		final top = y + head();
		final tall = bandTall();
		final wide = (width - metrics.inset * 2) / WHERE.length;
		final button = tall - metrics.gap * 2;

		for (which in 0...WHERE.length) {
			final where = x + metrics.inset + which * wide;

			paint.roundedRect(where + 1, top + metrics.gap, wide - 2, button,
				metrics.radiusSmall, which == lands ? theme.accent : theme.raise2,
				(which == lands ? 0.85 : 1) * alpha);

			paint.textCentred(translate(WHERE[which]), where + wide * 0.5,
				top + metrics.gap + (button - small.height) * 0.5 + small.ascent,
				which == lands ? theme.ink : theme.dim, alpha);
		}
	}

	/**
		Draws the strands, clipped to the room there is for them.

		@param paint What to draw with.
		@param theme The colours.
		@param metrics The measurements.
		@param small The face to write in.
		@param alpha How far the sheet has faded in.
	**/
	function listed(paint:Paint, theme:Theme, metrics:mdd.ui.Metrics, small:mdd.ui.Font,
			alpha:Float):Void {
		final top = listTop();
		final tall = rowTall();
		final room = shown() * tall;

		paint.pushClip(x, top, width, room);

		final box = metrics.whole(14);
		final chooser = chooserAt(metrics);

		for (index in 0...shown()) {
			final at = offset + index;
			if (at >= strands.length) break;

			final strand = strands[at];
			final line = top + index * tall;
			final middle = line + tall * 0.5;

			if (at == hoverAt) {
				paint.rect(x, line, width, tall, theme.accent, Theme.HOVER * alpha);
			}

			paint.roundedRect(x + metrics.inset, middle - box * 0.5, box, box,
				metrics.radiusSmall, strand.taken ? theme.accent : theme.raise2, alpha);

			final text = middle - small.height * 0.5 + small.ascent;
			final left = x + metrics.inset + box + metrics.gap * 2;

			paint.pushClip(left, line, chooser - left - metrics.gap, tall);
			paint.text(strand.titled(), left, text,
				strand.taken ? theme.ink : theme.dim, alpha);
			paint.popClip();

			paint.textRight(said(strand), chooser - metrics.gap * 2, text, theme.dim,
				alpha * 0.8);

			paint.roundedRect(chooser, middle - box, metrics.whole(CHOOSER), box * 2,
				metrics.radiusSmall, theme.raise2, alpha * (strand.taken ? 1 : 0.4));

			paint.textCentred("‹", chooser + metrics.whole(12), text, theme.dim,
				alpha * (strand.taken ? 1 : 0.4));

			paint.textCentred(named(strand.part), chooser + metrics.whole(CHOOSER) * 0.5,
				text, strand.taken ? theme.ink : theme.dim,
				alpha * (strand.taken ? 1 : 0.5));

			paint.textCentred("›", chooser + metrics.whole(CHOOSER - 12), text,
				theme.dim, alpha * (strand.taken ? 1 : 0.4));
		}

		paint.popClip();
	}

	/**
		@param part A part, by index.
		@return What it is called.
	**/
	static function named(part:Int):String {
		final held:Part = part;
		return held.name();
	}

	/**
		@param strand One strand.
		@return What it holds, in one line: how many notes, and the range they cover.
	**/
	function said(strand:Strand):String {
		if (strand.notes == 0) return "";

		return filled(strand.drums() ? Locale.IMPORT_DRUMS : Locale.IMPORT_NOTES,
			["" + strand.notes, "" + (strand.channel + 1)]);
	}
}
