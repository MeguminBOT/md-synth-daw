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
		What the number is in, drawn straight after it, so a unit that wants a space before it
		carries one. A number that turns its value into words through `derived` shows those instead,
		without it.
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
		What turns the raw value into what it means, for the tooltip. It is asked again only when
		the value or the language changes, when it is replaced, or when `rederive` is called.
	**/
	public var derived(default, set):Null<Int -> String> = null;

	/**
		What turns typed text back into a raw value, where the number is shown in
		units of its own rather than in its raw steps.

		Without it, what is typed is the raw value, and a field drawn in seconds but
		held in twentieths reads a typed 2 as a tenth of a second.
	**/
	public var typed:Null<String -> Null<Int>> = null;

	var dragging:Bool = false;
	var grabY:Float = 0;
	var grabValue:Int = 0;

	var entry:String = "";

	var plainValue:Int = 0;
	var plainUnit:Null<String> = null;
	var plainText:String = "";

	var meantValue:Int = 0;
	var meantIn:Null<String> = null;
	var meantText:String = "";

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
		precision = 4;
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
				return true;

			case Kind.PointerMove:
				if (!dragging) return false;

				set(grabValue + Std.int((grabY - event.y) / 2.0));
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
		Takes what was typed, in whatever the number is shown in, and stops
		typing. Text that reads as no number leaves the value alone.
	**/
	function commits():Void {
		final want = typed == null ? Std.parseInt(entry) : typed(entry);
		if (want != null) set(want);

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
		Keeps what was typed when the keyboard goes elsewhere, rather than leaving
		the field sitting with a caret in it for the rest of the session.

		@param on Whether it now has the keyboard.
	**/
	override public function focused(on:Bool):Void {
		if (!on && typing) commits();
		super.focused(on);
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

		final said = shown();
		final wide = small.measure(label) + mono.measure(said) + metrics.unit * 4
			+ metrics.inset;
		final least = metrics.whole(70);

		return wide < least ? least : wide;
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

	/**
		@return What the number shows while nobody is typing into it: what `derived` makes of its
			value, or the value with its unit after it.
	**/
	public function shown():String {
		return derived != null ? meant() : plain(unit);
	}

	function set_derived(next:Null<Int -> String>):Null<Int -> String> {
		derived = next;
		meantIn = null;

		return next;
	}

	/**
		Asks `derived` again on the next frame, which an owner whose words for a value follow
		something besides the value and the language calls when that changes.
	**/
	public function rederive():Void {
		meantIn = null;
		invalidate();
	}

	/**
		@return What `derived` makes of the value, asked again only when the value or the language
			has changed or `rederive` was called. A call into a function held in a variable boxes
			the string it returns, so asking on every frame would allocate on every frame.
	**/
	function meant():String {
		final root = root();
		final language = root == null ? "" : root.translation.language;
		final now = value;

		if (meantIn == null || now != meantValue || language != meantIn) {
			meantText = derived(now);
			meantValue = now;
			meantIn = language;
		}

		return meantText;
	}

	/**
		The value as digits, built again only when the value or the unit has changed since the
		last time, so a number sitting still draws without allocating.

		@param after What follows the digits.
		@return The value and `after`.
	**/
	function plain(after:String):String {
		final now = value;

		if (plainUnit == null || now != plainValue || plainUnit != after) {
			plainText = Std.string(now) + after;
			plainValue = now;
			plainUnit = after;
		}

		return plainText;
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
		final said = typing ? entry + "_" : (stacked && derived != null ? plain("") : shown());

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
			paint.text(meant(), x + metrics.unit * 2,
				y + height - metrics.unit - small.descent, theme.dim);
		}
	}
}
