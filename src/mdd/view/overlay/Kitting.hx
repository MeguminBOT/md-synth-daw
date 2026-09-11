package mdd.view.overlay;

import mdd.app.Locale;
import mdd.format.Kit;
import mdd.format.Slot;
import mdd.ui.Input;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Motion;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;
import mdd.ui.control.Button;

@:unreflective

/**
	The kit sheet: a folder of recordings, what each one will become, and what the whole
	of it comes to.

	Nothing is written until the sheet is closed with the button, so a folder can be
	looked at and left alone. The keys are worked out from the recordings when it
	opens, and the button that does it is there because a guess is a guess: a row's key
	steps by hand whenever the guess is wrong.
**/
final class Kitting extends Widget {
	/**
		How many rows are shown before it scrolls.
	**/
	static inline final SHOWN = 12;

	/**
		The rates offered, which are the ones Mega Drive drivers actually take. 14000 is
		what the XGM driver plays at, so a kit made there reaches a driver without being
		converted a second time.
	**/
	public static final RATES:Array<Int> = [8000, 11025, 13400, 14000, 16000, 22050];

	/**
		What is being made. Empty until `ask` is called.
	**/
	public var kit:Kit = new Kit();

	/**
		The button that saves the kit.
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
		Called with the kit when it is saved.
	**/
	public var onSave:Null<Kit -> Void> = null;

	/**
		Called when the sheet closes without saving.
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
		Shows the sheet for a kit that has been read and measured.

		@param held The kit.
	**/
	public function ask(held:Kit):Void {
		kit = held;

		offset = 0;
		hoverAt = -1;

		final root = root();
		if (root == null) return;

		go.label = root.translate(Locale.FILE_SAVE);
		stop.label = root.translate(Locale.EXPORT_CANCEL);

		rise.hold(0);
		fade.hold(0);

		root.start(rise, 1, Motion.ENTER);
		root.start(fade, 1, Motion.ENTER);

		relayout();
	}

	/**
		Closes the sheet without saving.
	**/
	public function shut():Void {
		final root = root();
		if (root != null) root.lower();

		if (onShut != null) onShut();
	}

	function fired():Void {
		if (kit.taken() == 0) return;

		final held = kit;
		final what = onSave;

		shut();

		if (what != null) what(held);
	}

	/**
		@return How many rows are on screen.
	**/
	public function shown():Int {
		return kit.slots.length < SHOWN ? kit.slots.length : SHOWN;
	}

	/**
		@return How tall one row is.
	**/
	public function rowTall():Float {
		final root = root();
		return root == null ? 28 : root.metrics.whole(28);
	}

	/**
		@return How tall the title band is.
	**/
	public function head():Float {
		final root = root();
		return root == null ? 46 : root.metrics.whole(46);
	}

	/**
		@return How tall the row of settings is.
	**/
	public function bandTall():Float {
		final root = root();
		return root == null ? 40 : root.metrics.whole(40);
	}

	override function measure(availableWidth:Float, availableHeight:Float):Void {
		final root = root();
		final metrics = root == null ? null : root.metrics;

		wantWidth = metrics == null ? 640 : metrics.whole(640);
		wantHeight = metrics == null ? 480
			: head() + bandTall() + shown() * rowTall() + metrics.whole(34)
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

	function listTop():Float {
		return y + head() + bandTall();
	}

	function rowAt(py:Float):Int {
		final top = listTop();
		if (py < top) return -1;

		final at = offset + Std.int((py - top) / rowTall());
		return at >= 0 && at < kit.slots.length && py < top + shown() * rowTall() ? at : -1;
	}

	/**
		How wide the key stepper is.
	**/
	public static inline final KEYED = 110;

	/**
		@param metrics What to measure with.
		@return Where the key stepper starts, across.
	**/
	public function keyedAt(metrics:Metrics):Float {
		return x + width - metrics.inset - metrics.whole(KEYED);
	}

	/**
		Steps the rate to the next one offered, wrapping.

		@param by Which way.
	**/
	public function rated(by:Int):Void {
		var at = RATES.indexOf(kit.rate);
		if (at < 0) at = 0;

		kit.rate = RATES[(at + by + RATES.length) % RATES.length];

		kit.converts();
		invalidate();
	}

	override function took(event:Input):Bool {
		final root = root();
		if (root == null) return false;

		final metrics = root.metrics;

		switch (event.kind) {
			case Kind.Wheel:
				final most = kit.slots.length - shown();
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
					banded(event.x, metrics);
					return true;
				}

				final at = rowAt(event.y);
				if (at < 0) return true;

				final slot = kit.slots[at];
				final keyed = keyedAt(metrics);

				if (event.x >= keyed) {
					final half = keyed + metrics.whole(KEYED) * 0.5;
					final by = event.x < half ? -1 : 1;

					slot.root += by;

					if (slot.root < 0) slot.root = 0;
					if (slot.root > 127) slot.root = 127;

					final made = slot.made;
					if (made != null) made.root = slot.root;
				} else {
					slot.taken = !slot.taken;
					kit.converts();
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

	/**
		Takes a press on the row of settings.

		@param px Where it landed, across.
		@param metrics What to measure with.
	**/
	function banded(px:Float, metrics:Metrics):Void {
		final wide = (width - metrics.inset * 2) / 3;
		final which = Std.int((px - x - metrics.inset) / wide);

		if (which == 0) {
			rated(px < x + metrics.inset + wide * 0.5 ? -1 : 1);
			return;
		}

		if (which == 1) {
			kit.drums = !kit.drums;
			kit.guesses();
			kit.converts();

			invalidate();
			return;
		}

		kit.guesses();
		kit.converts();

		invalidate();
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

		final large = metrics.large == null ? metrics.body : metrics.large;
		final font = metrics.body;
		final small = metrics.small == null ? font : metrics.small;

		paint.reface(large);
		paint.text(kit.name == "" ? translate(Locale.KIT) : kit.name, x + metrics.inset,
			y + metrics.inset + large.ascent, theme.ink, alpha);

		settings(paint, theme, metrics, alpha);
		rows(paint, theme, metrics, alpha, font, small);
		room(paint, theme, metrics, alpha, small);

		for (child in children) {
			if (child.visible) child.paint(paint);
		}

		paint.popTransform();
	}

	function settings(paint:Paint, theme:Theme, metrics:Metrics, alpha:Float):Void {
		final font = metrics.small == null ? metrics.body : metrics.small;
		final top = y + head();
		final tall = bandTall();
		final wide = (width - metrics.inset * 2) / 3;

		paint.reface(font);

		final said = [translate(Locale.KIT_RATE) + "  " + kit.rate,
			translate(Locale.KIT_DRUMS), translate(Locale.KIT_GUESS)];

		for (which in 0...3) {
			final left = x + metrics.inset + which * wide;
			final lit = which == 1 && kit.drums;

			if (lit) {
				paint.roundedRect(left, top + metrics.unit, wide - metrics.gap,
					tall - metrics.unit * 2, metrics.radiusRow, theme.accent, Theme.SELECT);
			}

			paint.outline(left, top + metrics.unit, wide - metrics.gap,
				tall - metrics.unit * 2, lit ? theme.accent : theme.frame, metrics.whole(1),
				alpha, metrics.radiusRow);

			paint.fitted(font, metrics.condensed, said[which], "",
				left + metrics.gap, top + tall * 0.5, wide - metrics.gap * 3,
				lit ? theme.ink : theme.dim, alpha * 0.9);
		}
	}

	function rows(paint:Paint, theme:Theme, metrics:Metrics, alpha:Float, font:mdd.ui.Font,
			small:mdd.ui.Font):Void {
		final top = listTop();
		final tall = rowTall();
		final keyed = keyedAt(metrics);

		paint.pushClip(x, top, width, shown() * tall);

		for (index in 0...shown()) {
			final at = offset + index;
			if (at >= kit.slots.length) break;

			final slot = kit.slots[at];
			final row = top + index * tall;

			if (at == hoverAt) {
				paint.roundedRect(x + metrics.inset, row, width - metrics.inset * 2, tall - 2,
					metrics.radiusRow, theme.accent, Theme.HOVER);
			}

			final tick = x + metrics.inset + metrics.gap;
			final box = metrics.whole(12);
			final middle = row + tall * 0.5;

			paint.outline(tick, middle - box * 0.5, box, box,
				slot.taken ? theme.accent : theme.frame, metrics.whole(1), alpha,
				metrics.radiusSmall);

			if (slot.taken) {
				paint.roundedRect(tick + metrics.whole(3), middle - box * 0.5 + metrics.whole(3),
					box - metrics.whole(6), box - metrics.whole(6), metrics.radiusSmall,
					theme.accent, alpha);
			}

			paint.reface(font);
			paint.fitted(font, metrics.condensed, slot.name, "",
				tick + box + metrics.gap, middle, keyed - tick - box - metrics.gap * 3,
				slot.taken ? theme.ink : theme.dim, alpha * (slot.taken ? 1 : 0.6));

			paint.reface(small);

			final made = slot.made;
			final bytes = made == null ? 0 : made.length();

			paint.textRight(bytes == 0 ? "" : bytes + " b",
				keyed - metrics.gap * 2, middle - small.height * 0.5 + small.ascent,
				theme.dim, alpha * 0.7);

			paint.textCentred(slot.root < 0 ? "" : named(slot.root),
				keyed + metrics.whole(KEYED) * 0.5,
				middle - small.height * 0.5 + small.ascent,
				slot.taken ? theme.ink : theme.dim, alpha * 0.9);
		}

		paint.popClip();
	}

	function room(paint:Paint, theme:Theme, metrics:Metrics, alpha:Float,
			small:mdd.ui.Font):Void {
		final bytes = kit.bytes();
		final ceiling = mdd.check.Profile.ROM;
		final over = ceiling > 0 && bytes > ceiling;

		final line = listTop() + shown() * rowTall() + metrics.gap;

		paint.reface(small);
		paint.text(filled(Locale.KIT_ROOM, ["" + bytes, "" + ceiling]), x + metrics.inset,
			line + small.ascent, over ? theme.warn : theme.dim, alpha * (over ? 1 : 0.8));

		final wide = width - metrics.inset * 2;
		final part = ceiling <= 0 ? 0.0 : bytes / ceiling;
		final full = part > 1 ? 1.0 : part;

		final bar = line + small.height + metrics.unit;

		paint.rect(x + metrics.inset, bar, wide, metrics.whole(3), theme.sink, alpha * 0.5);
		paint.rect(x + metrics.inset, bar, wide * full, metrics.whole(3),
			over ? theme.warn : theme.accent, alpha);
	}

	static final LETTERS:Array<String> = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#",
		"A", "A#", "B"];

	/**
		@param pitch A key.
		@return What it is called, with the number general MIDI counts by.
	**/
	static function named(pitch:Int):String {
		return LETTERS[pitch % 12] + Std.int(pitch / 12 - 1) + "  " + pitch;
	}
}
