package mdd.ui.control;

@:unreflective

/**
	Two numbers in one field, written one over the other as 7/8: an upper one from a span, and a
	lower one from a list of the values it may take.

	It is drawn as a `Number` is and handled the same way, one half at a time: the half under the
	pointer is the one a drag, the wheel or the arrow keys move, the upper by one and the lower
	through its list, and a double click types both at once.
**/
final class Fraction extends Widget {
	/**
		What it is called, drawn small before the numbers. It may be empty.
	**/
	public var label:String;

	/**
		The upper number.
	**/
	public var upper(default, null):Int = 1;

	/**
		The lower number, always one of `lowers`.
	**/
	public var lower(default, null):Int = 1;

	/**
		The smallest the upper number goes.
	**/
	public final least:Int;

	/**
		The largest the upper number goes.
	**/
	public final most:Int;

	/**
		Every value the lower number may take, in the order a drag or the wheel steps through them.
	**/
	public final lowers:Array<Int>;

	/**
		Called when either number changes, once for each change.
	**/
	public var onChange:Null<Fraction -> Void> = null;

	/**
		How far the pointer travels for one step of the upper number, in pixels.
	**/
	static inline final UPPER_TRAVEL = 4.0;

	/**
		How far it travels for one step of the lower number, which has few enough values that each
		wants to be found on purpose.
	**/
	static inline final LOWER_TRAVEL = 12.0;

	var dragging:Bool = false;
	var draggingLower:Bool = false;
	var grabY:Float = 0;
	var grabUpper:Int = 0;
	var grabLower:Int = 0;

	var overLower:Bool = false;
	var entry:String = "";

	var shownUpper:Int = -1;
	var shownLower:Int = -1;
	var upperText:String = "";
	var lowerText:String = "";

	/**
		Builds one.

		@param label What it is called.
		@param upper The upper number it starts on.
		@param lower The lower number it starts on, read as the first of `lowers` where it is none
			of them.
		@param least The smallest the upper number goes.
		@param most The largest.
		@param lowers Every value the lower number may take, at least one.
	**/
	public function new(label:String, upper:Int, lower:Int, least:Int, most:Int, lowers:Array<Int>) {
		super();
		this.label = label;
		this.least = least;
		this.most = most;
		this.lowers = lowers.length == 0 ? [1] : lowers;
		focusable = true;
		opaque = true;
		precision = 4;
		sets(upper, lower);
	}

	/**
		Changes both numbers, the upper clamped to its span and the lower read as the first of
		`lowers` where it is none of them, telling `onChange` once where either moved.

		@param upper The upper number.
		@param lower The lower number.
	**/
	public function sets(upper:Int, lower:Int):Void {
		final nextUpper = upper < least ? least : (upper > most ? most : upper);
		final nextLower = lowers.indexOf(lower) >= 0 ? lower : lowers[0];

		if (nextUpper == this.upper && nextLower == this.lower) return;

		this.upper = nextUpper;
		this.lower = nextLower;
		invalidate();

		if (onChange != null) onChange(this);
	}

	/**
		Steps the lower number through `lowers`, stopping at either end.

		@param from Where in `lowers` to count from.
		@param by How many places to move.
	**/
	function stepsLower(from:Int, by:Int):Void {
		var at = from + by;
		if (at < 0) at = 0;
		if (at >= lowers.length) at = lowers.length - 1;

		sets(upper, lowers[at]);
	}

	/**
		A fraction is dragged up and down until it is being typed in.

		@param px A point, across.
		@param py A point, down.
		@return Which cursor shape belongs there.
	**/
	override function cursorAt(px:Float, py:Float):Int {
		return typing ? mdd.host.Sdl.CURSOR_TEXT : mdd.host.Sdl.CURSOR_DOWN;
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				if (event.button != Pointer.Left) return false;

				if (event.clicks >= 2) {
					dragging = false;
					typing = true;
					entry = "";
					invalidate();
					return true;
				}

				dragging = true;
				draggingLower = lowerAt(event.x);
				grabY = event.y;
				grabUpper = upper;
				grabLower = lowers.indexOf(lower);
				invalidate();
				return true;

			case Kind.PointerMove:
				if (!dragging) {
					final now = lowerAt(event.x);

					if (now != overLower) {
						overLower = now;
						invalidate();
					}

					return false;
				}

				if (draggingLower) {
					stepsLower(grabLower, Std.int((grabY - event.y) / LOWER_TRAVEL));
				} else {
					sets(grabUpper + Std.int((grabY - event.y) / UPPER_TRAVEL), lower);
				}

				return true;

			case Kind.PointerUp:
				if (!dragging) return false;

				dragging = false;
				invalidate();
				return true;

			case Kind.Wheel:
				final step = event.dy > 0 ? 1 : (event.dy < 0 ? -1 : 0);

				if (lowerAt(event.x)) stepsLower(lowers.indexOf(lower), step);
				else sets(upper + step, lower);

				return true;

			case Kind.Text:
				if (!typing) return false;

				entry += event.said;
				invalidate();
				return true;

			case Kind.KeyDown:
				return keyed(event);

			case _:
		}

		return false;
	}

	/**
		@param px A point, across.
		@return Whether it is over the lower number, which is the stroke and everything right of it.
	**/
	function lowerAt(px:Float):Bool {
		final root = root();
		final mono = root == null ? null : root.metrics.mono;
		if (mono == null) return px > x + width * 0.5;

		texts();

		final right = x + width - root.metrics.unit * 2;
		return px >= right - mono.measure(lowerText) - mono.measure("/");
	}

	/**
		Takes what was typed and stops typing: both numbers as 7/8, or the upper one alone. Text
		that reads as neither, or a lower number `lowers` does not hold, leaves both alone.
	**/
	function commits():Void {
		final written = ~/^\s*(\d{1,4})\s*(?:\/\s*(\d{1,4})\s*)?$/;

		if (written.match(entry)) {
			final typedUpper:Int = Std.parseInt(written.matched(1));
			final typedLower:Null<Int> = written.matched(2) == null ? null : Std.parseInt(written.matched(2));

			if (typedLower == null) sets(typedUpper, lower);
			else if (lowers.indexOf(typedLower) >= 0) sets(typedUpper, typedLower);
		}

		sheds();
	}

	/**
		Stops typing and throws away what was typed.
	**/
	function sheds():Void {
		if (!typing) return;

		typing = false;
		entry = "";
		invalidate();
	}

	/**
		Keeps what was typed when the keyboard goes elsewhere.

		@param on Whether it now has the keyboard.
	**/
	override public function focused(on:Bool):Void {
		if (!on && typing) commits();
		super.focused(on);
	}

	/**
		@param on Whether the pointer is now over it.
	**/
	override public function hovered(on:Bool):Void {
		super.hovered(on);
		invalidate();
	}

	/**
		Handles typing into it, and the arrow keys: up and down move the upper number, and with
		`Shift` held the lower one.

		@param event The event.
		@return Whether it was taken.
	**/
	function keyed(event:Input):Bool {
		if (typing) {
			switch (event.code) {
				case Key.Return:
					commits();
					return true;

				case Key.Escape:
					sheds();
					return true;

				case Key.Backspace:
					if (entry.length > 0) entry = entry.substring(0, entry.length - 1);
					invalidate();
					return true;

				case _:
			}

			return false;
		}

		final step = switch (event.code) {
			case Key.Up: 1;
			case Key.Down: -1;
			case _: 0;
		}

		if (step == 0) return false;

		if (event.shift()) stepsLower(lowers.indexOf(lower), step);
		else sets(upper + step, lower);

		return true;
	}

	/**
		Builds the two numbers' text again only where one of them changed, so a fraction sitting
		still draws without allocating.
	**/
	function texts():Void {
		if (upper != shownUpper) {
			upperText = Std.string(upper);
			shownUpper = upper;
		}

		if (lower != shownLower) {
			lowerText = Std.string(lower);
			shownLower = lower;
		}
	}

	/**
		@return How wide it needs to be for the widest pair it could show.
	**/
	public function fits():Float {
		final root = root();
		if (root == null) return 70;

		final metrics = root.metrics;
		final mono = metrics.mono;
		final small = metrics.small;
		if (mono == null || small == null) return 70;

		var widest = 1;
		for (one in lowers) if (one > widest) widest = one;

		final wide = small.measure(label) + mono.measure(Std.string(most) + "/" + widest)
			+ metrics.unit * 4 + metrics.inset;
		final floor = metrics.whole(70);

		return wide < floor ? floor : wide;
	}

	/**
		Wants the width `fits` gives and whatever height it is offered.

		@param availableWidth How much room there is, across.
		@param availableHeight How much room there is, down.
	**/
	override function measure(availableWidth:Float, availableHeight:Float):Void {
		wantWidth = fits();
		wantHeight = availableHeight;
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final mono = metrics.mono;
		final small = metrics.small;
		if (mono == null || small == null) return;

		final over = root.over == this;

		paint.roundedRect(x, y, width, height, metrics.radiusRow, theme.sink);
		if (over) paint.roundedRect(x, y, width, height, metrics.radiusRow, theme.accent, Theme.HOVER);

		paint.outline(x, y, width, height, root.focus == this || dragging ? theme.accent : theme.frame,
			metrics.whole(1), 1, metrics.radiusRow);

		paint.reface(small);
		paint.text(label, x + metrics.unit * 2, y + (height - small.height) * 0.5 + small.ascent, theme.dim,
			0.7);

		final right = x + width - metrics.unit * 2;
		final baseline = y + (height - mono.height) * 0.5 + mono.ascent;

		paint.reface(mono);

		if (typing) {
			paint.textRight(entry + "_", right, baseline, theme.accent, 0.85);
			return;
		}

		texts();

		final lowerHot = dragging ? draggingLower : over && overLower;
		final upperHot = dragging ? !draggingLower : over && !overLower;
		final lowerLeft = right - mono.measure(lowerText);
		final slashLeft = lowerLeft - mono.measure("/");

		paint.textRight(lowerText, right, baseline, lowerHot ? theme.accent : theme.ink, 0.85);
		paint.textRight("/", lowerLeft, baseline, theme.dim, 0.85);
		paint.textRight(upperText, slashLeft, baseline, upperHot ? theme.accent : theme.ink, 0.85);
	}
}
