package mdd.ui.control;

@:unreflective

/**
	A number that can be dragged or typed into.

	Typing is what makes it worth having over a knob: a fade of exactly two seconds is
	a thing to type, not a thing to find by dragging. `derived` is what turns the raw
	value into what it means, which is how a total level shows its decibels.
**/
final class Number extends Widget implements Range {
	/**
		What it is called.
	**/
	public var label:String;

	/**
		What the number is in, drawn after it.
	**/
	public var unit:String = "";

	/**
		Where it sits now.
	**/
	public var value(get, never):Int;

	var carried:Int = 0;

	/**
		The smallest it goes.
	**/
	public var least(default, null):Int = 0;

	/**
		The largest.
	**/
	public var most(default, null):Int = 127;

	/**
		Called when the value changes.
	**/
	public var onChange:Null<Number -> Void> = null;

	/**
		What turns the raw value into what it means, for the tooltip.
	**/
	public var derived:Null<Int -> String> = null;

	var dragging:Bool = false;
	var grabY:Float = 0;
	var grabValue:Int = 0;
	var fine:Bool = false;

	var entry:String = "";

	/**
		Builds a number.

		@param label What it is called.
		@param value Where it starts.
		@param least The smallest it goes.
		@param most The largest.
	**/
	public function new(label:String, value:Int, least:Int, most:Int) {
		super();
		this.label = label;
		this.least = least;
		this.most = most;
		focusable = true;
		opaque = true;
		set(value);
	}

	/**
		Changes the range, clamping the value into it.

		@param least The smallest it goes.
		@param most The largest.
	**/
	public function spans(least:Int, most:Int):Void {
		if (this.least == least && this.most == most) return;

		this.least = least;
		this.most = most;

		set(carried);
		invalidate();
	}

	/**
		@return How far it can move.
	**/
	public inline function span():Int {
		return most - least;
	}

	/**
		@return How far along it is, 0 to 1.
	**/
	public function share():Float {
		final run = span();
		return run == 0 ? 0 : (carried - least) / run;
	}

	/**
		@return Where it sits now.
	**/
	function get_value():Int {
		return carried;
	}

	/**
		Moves it, clamped to the range, telling `onChange` only where it actually moved.

		@param next Where to move it to.
	**/
	public function set(next:Int):Void {
		var held = next;
		if (held < least) held = least;
		if (held > most) held = most;

		if (held == carried) return;
		carried = held;
		invalidate();
		if (onChange != null) onChange(this);
	}

	/**
		A number is dragged up and down until it is being typed in.

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
					typing = true;
					entry = "";
					invalidate();
					return true;
				}

				dragging = true;
				grabY = event.y;
				grabValue = carried;
				fine = event.ctrl();
				return true;

			case Kind.PointerMove:
				if (!dragging) return false;

				final moved = grabY - event.y;
				final step = fine ? 8.0 : 2.0;
				set(grabValue + Std.int(moved / step));
				return true;

			case Kind.PointerUp:
				if (!dragging) return false;
				dragging = false;
				return true;

			case Kind.Wheel:
				set(carried + Std.int(event.dy) * (event.ctrl() ? 1 : 4));
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
		Handles typing into it: digits, a minus sign, backspace, enter and escape.

		@param event The event.
		@return Whether it was taken.
	**/
	function keyed(event:Input):Bool {
		if (typing) {
			switch (event.code) {
				case Key.Return:
					final read = Std.parseInt(entry);
					if (read != null) set(read);
					typing = false;
					invalidate();
					return true;

				case Key.Escape:
					typing = false;
					invalidate();
					return true;

				case Key.Backspace:
					if (entry.length > 0) entry = entry.substring(0, entry.length - 1);
					invalidate();
					return true;

				case _:
			}
			return false;
		}

		switch (event.code) {
			case Key.Up:
				set(value + (event.ctrl() ? 1 : 4));
				return true;

			case Key.Down:
				set(value - (event.ctrl() ? 1 : 4));
				return true;

			case _:
		}
		return false;
	}

	/**
		@return How wide it needs to be for the widest value it could show.
	**/
	public function fits():Float {
		final root = root();
		if (root == null) return 70;

		final metrics = root.metrics;
		final mono = metrics.mono;
		final small = metrics.small;

		if (mono == null || small == null) return 70;

		final said = derived != null ? derived(value) : Std.string(value);
		final wide = small.measure(label) + mono.measure(said) + metrics.unit * 4
			+ metrics.inset;
		final least = metrics.whole(70);

		return wide < least ? least : wide;
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final mono = metrics.mono;
		final small = metrics.small;
		if (mono == null || small == null) return;

		paint.roundedRect(x, y, width, height, metrics.radiusRow, theme.sink);

		if (root.over == this) {
			paint.roundedRect(x, y, width, height, metrics.radiusRow, theme.accent, Theme.HOVER);
		}

		paint.outline(x, y, width, height,
			root.focus == this || dragging ? theme.accent : theme.frame, metrics.whole(1), 1,
			metrics.radiusRow);

		final stacked = height >= small.height + mono.height + metrics.unit * 3;
		final said = typing ? entry + "_"
			: (derived != null && !stacked ? derived(value) : Std.string(value));

		if (!stacked) {
			paint.reface(small);
			paint.text(label, x + metrics.unit * 2,
				y + (height - small.height) * 0.5 + small.ascent, theme.dim, 0.7);

			paint.reface(mono);
			paint.textRight(said, x + width - metrics.unit * 2,
				y + (height - mono.height) * 0.5 + mono.ascent,
				typing ? theme.accent : theme.ink, 0.85);
			return;
		}

		paint.reface(small);
		paint.text(label, x + metrics.unit * 2, y + metrics.unit + small.ascent, theme.dim);

		paint.reface(mono);
		paint.textRight(said, x + width - metrics.unit * 2,
			y + height - metrics.unit - mono.descent, typing ? theme.accent : theme.ink);

		if (derived != null && !typing) {
			paint.reface(small);
			paint.text(derived(value), x + metrics.unit * 2,
				y + height - metrics.unit - small.descent, theme.dim);
		}
	}
}
