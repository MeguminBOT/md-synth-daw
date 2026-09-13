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
import mdd.ui.control.Choice;
import mdd.ui.control.Field;
import mdd.ui.control.Menu;

@:unreflective

/**
	The kit sheet: recordings on their way to being a bank, what each one will become,
	and what the whole of it comes to.

	It opens empty and is filled from it, a file or a folder at a time, because a kit is
	as often gathered from several places as it is found sitting in one. Nothing is
	written until the sheet is closed with the button.

	Every control here is a real one. A hit is put on a key as it arrives, from its name
	where the name spells a note and from the recording where it does not. Detect keys
	does that again for all of them, and a row's key steps by hand wherever it landed wrong.
**/
final class Kitting extends Widget {
	/**
		How many rows are shown before it scrolls.
	**/
	static inline final SHOWN = 10;

	/**
		The rates offered, which are the ones Mega Drive drivers actually take. 14000 is
		what the XGM driver plays at, so a kit made there reaches a driver without being
		converted a second time.
	**/
	public static final RATES:Array<Int> = [8000, 11025, 13400, 14000, 16000, 22050];

	/**
		What is being made.
	**/
	public var kit:Kit = new Kit();

	/**
		What the bank will be called.
	**/
	public final named:Field;

	/**
		What every hit in it is tagged with, separated by commas.
	**/
	public final tagged:Field;

	/**
		Opens the rates.
	**/
	public final rate:Button;

	/**
		Whether the keys are the ones general MIDI puts drums on.
	**/
	public final drums:Button;

	/**
		Puts every hit on a key again, which undoes any key stepped by hand.
	**/
	public final detect:Button;

	/**
		Adds one recording.
	**/
	public final adds:Button;

	/**
		Adds every recording in a folder.
	**/
	public final folder:Button;

	/**
		Saves the kit.
	**/
	public final go:Button;

	/**
		Closes the sheet.
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

	/**
		Called to ask for one recording to add.
	**/
	public var onAdd:Null<Void -> Void> = null;

	/**
		Called to ask for a folder of them.
	**/
	public var onFolder:Null<Void -> Void> = null;

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

		named = new Field("");
		tagged = new Field("");

		named.onChange = function(said:String):Void kit.name = said;
		tagged.onChange = function(said:String):Void kit.tags = said;

		rate = new Button("");
		drums = new Button("");
		detect = new Button("");
		adds = new Button("");
		folder = new Button("");

		drums.toggle = true;

		go = new Button("");
		stop = new Button("");

		add(named);
		add(tagged);
		add(rate);
		add(drums);
		add(detect);
		add(adds);
		add(folder);
		add(go);
		add(stop);

		rate.onFire = function(button:Button):Void rates();
		drums.onFire = function(button:Button):Void kitted(button.on);
		detect.onFire = function(button:Button):Void detected();
		adds.onFire = function(button:Button):Void asked(false);
		folder.onFire = function(button:Button):Void asked(true);

		go.onFire = function(button:Button):Void fired();
		stop.onFire = function(button:Button):Void shut();
	}

	/**
		Shows the sheet.

		@param held What to fill it with, which is an empty kit where one is being
			started from nothing.
	**/
	public function ask(held:Kit):Void {
		kit = held;

		offset = 0;
		hoverAt = -1;

		named.set(kit.name);
		tagged.set(kit.tags);

		drums.on = kit.drums;

		labelled();

		rise.hold(0);
		fade.hold(0);

		final root = root();
		if (root == null) return;

		root.start(rise, 1, Motion.ENTER);
		root.start(fade, 1, Motion.ENTER);

		relayout();
	}

	/**
		Adds one recording to what is open, measures it, and gives it a key.

		@param path The file.
		@return Whether it read.
	**/
	public function takes(path:String):Bool {
		if (!kit.adds(path, Kit.titled(path))) {
			invalidate();
			return false;
		}

		kit.detects();
		kit.converts();

		named.set(kit.name);

		relayout();
		return true;
	}

	/**
		Adds every recording in a folder to what is open.

		@param where The folder.
		@return How many read.
	**/
	public function takesFolder(where:String):Int {
		final many = kit.reads(where);

		if (many > 0) {
			kit.detects();
			kit.converts();

			named.set(kit.name);
		}

		relayout();
		return many;
	}

	/**
		Puts the labels on every control, which changing the language or the rate needs.
	**/
	public function labelled():Void {
		final root = root();
		if (root == null) return;

		named.hint = root.translate(Locale.PRESET_BY_NAME);
		tagged.hint = root.translate(Locale.PRESET_TAGS);

		rate.label = root.translate(Locale.KIT_RATE) + "  " + kit.rate;
		drums.label = root.translate(Locale.KIT_DRUMS);
		detect.label = root.translate(Locale.KIT_DETECT);
		adds.label = root.translate(Locale.KIT_ADD);
		folder.label = root.translate(Locale.KIT_FOLDER);

		go.label = root.translate(Locale.FILE_SAVE);
		stop.label = root.translate(Locale.EXPORT_CANCEL);

		go.enabled = kit.taken() > 0;
		detect.enabled = kit.slots.length > 0;

		invalidate();
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

	function asked(whole:Bool):Void {
		final what = whole ? onFolder : onAdd;
		if (what != null) what();
	}

	function kitted(on:Bool):Void {
		kit.drums = on;

		kit.detects();
		kit.converts();

		labelled();
	}

	function detected():Void {
		kit.detects();
		kit.converts();

		labelled();
	}

	/**
		Offers the rates a driver takes.
	**/
	function rates():Void {
		final root = root();
		if (root == null) return;

		final menu = new Menu();

		for (which in RATES) {
			final choice = menu.offer(new Choice("" + which));

			if (which == kit.rate) choice.shortcut = "•";
			fires(choice, function():Void rated(which));
		}

		root.pop(menu, rate.x, rate.y + rate.height, this);
	}

	/**
		@param want The rate to convert at.
	**/
	public function rated(want:Int):Void {
		kit.rate = want;
		kit.converts();

		labelled();
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
		return root == null ? 44 : root.metrics.whole(44);
	}

	/**
		@return How tall one row of controls is.
	**/
	public function bandTall():Float {
		final root = root();
		return root == null ? 38 : root.metrics.whole(38);
	}

	/**
		How many rows of controls sit above the list.
	**/
	static inline final BANDS = 3;

	override function measure(availableWidth:Float, availableHeight:Float):Void {
		final root = root();
		final metrics = root == null ? null : root.metrics;

		wantWidth = metrics == null ? 640 : metrics.whole(640);
		wantHeight = metrics == null ? 480
			: head() + bandTall() * BANDS
			+ (shown() < 1 ? rowTall() * 2 : shown() * rowTall()) + metrics.whole(34)
			+ metrics.control + metrics.inset * 2;
	}

	override function layout():Void {
		final root = root();
		if (root == null) return;

		final metrics = root.metrics;
		final left = x + metrics.inset;
		final room = width - metrics.inset * 2;
		final tall = metrics.control;

		var top = y + head();
		final half = (room - metrics.gap) * 0.5;

		named.arrange(left, top, half, tall);
		tagged.arrange(left + half + metrics.gap, top, half, tall);

		top += bandTall();

		final third = (room - metrics.gap * 2) / 3;

		rate.arrange(left, top, third, tall);
		drums.arrange(left + third + metrics.gap, top, third, tall);
		detect.arrange(left + (third + metrics.gap) * 2, top, third, tall);

		top += bandTall();

		adds.arrange(left, top, half, tall);
		folder.arrange(left + half + metrics.gap, top, half, tall);

		final wide = metrics.whole(120);
		final bottom = y + height - metrics.inset - metrics.control;

		stop.arrange(x + width - metrics.inset - wide * 2 - metrics.gap, bottom, wide,
			metrics.control);
		go.arrange(x + width - metrics.inset - wide, bottom, wide, metrics.control);
	}

	function listTop():Float {
		return y + head() + bandTall() * BANDS;
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

				final at = rowAt(event.y);
				if (at < 0) return false;

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

					labelled();
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

		final large = metrics.large == null ? metrics.body : metrics.large;
		final font = metrics.body;
		final small = metrics.small == null ? font : metrics.small;

		paint.reface(large);
		paint.text(translate(Locale.KIT), x + metrics.inset,
			y + metrics.inset + large.ascent, theme.ink, alpha);

		if (kit.slots.length == 0) empty(paint, theme, metrics, alpha, small);
		else rows(paint, theme, metrics, alpha, font, small);

		room(paint, theme, metrics, alpha, small);

		for (child in children) {
			if (child.visible) child.paint(paint);
		}

		paint.popTransform();
	}

	function empty(paint:Paint, theme:Theme, metrics:Metrics, alpha:Float,
			small:mdd.ui.Font):Void {
		paint.reface(small);
		paint.textCentred(translate(Locale.KIT_EMPTY), x + width * 0.5,
			listTop() + rowTall() - small.height * 0.5 + small.ascent, theme.dim,
			alpha * 0.7);
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

			paint.textCentred(slot.root < 0 ? "" : keyName(slot.root),
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

		final line = listTop() + (shown() < 1 ? rowTall() * 2 : shown() * rowTall())
			+ metrics.gap;

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
	static function keyName(pitch:Int):String {
		return LETTERS[pitch % 12] + Std.int(pitch / 12 - 1) + "  " + pitch;
	}
}
