package mdd.ui.control;

@:unreflective

/**
	A knob: a value in a range, turned by dragging up and down.

	It implements `Range` through a property rather than a variable, because an
	interface cannot expose a variable to an `@:unreflective` implementer on hxcpp: the
	read answers null and nothing warns.
**/
final class Knob extends Widget implements Range {
	static inline final TRAVEL = 128.0;
	static inline final SWEEP = 4.712389;
	static inline final BEGAN = 2.356194;

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
		What it is called, drawn under it.
	**/
	public var label:String = "";

	/**
		Whether the sweep is drawn out from the middle, which is what a pan wants.
	**/
	public var centred:Bool = false;

	/**
		Called when the value changes.
	**/
	public var onChange:Null<Knob -> Void> = null;

	var dragging:Bool = false;
	var grabY:Float = 0;
	var grabValue:Int = 0;

	/**
		Builds a knob.

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
		carried = least - 1;
		set(value);
	}

	/**
		@return How far it can move.
	**/
	public inline function span():Int {
		return most - least;
	}

	/**
		@return How far round it is, 0 to 1.
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

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				if (event.button != Pointer.Left) return false;
				dragging = true;
				grabY = event.y;
				grabValue = carried;
				return true;

			case Kind.PointerMove:
				if (!dragging) return false;

				set(grabValue + Math.round((grabY - event.y) / TRAVEL * span()));
				return true;

			case Kind.PointerUp:
				if (!dragging) return false;
				dragging = false;
				return true;

			case Kind.Wheel:
				set(carried + Std.int(event.dy) * (event.ctrl() ? 1 : 4));
				return true;

			case _:
		}
		return false;
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final small = metrics.small;

		final labelTall = label == "" || small == null ? 0 : small.height + metrics.unit;
		final side = (width < height - labelTall ? width : height - labelTall);
		final radius = side * 0.42;
		final cx = x + width * 0.5;
		final cy = y + radius + metrics.unit;
		final weight = metrics.whole(4);

		paint.arc(cx, cy, radius, BEGAN, BEGAN + SWEEP, weight, theme.frame);

		if (centred) {
			final middle = BEGAN + SWEEP * 0.5;
			final to = BEGAN + SWEEP * share();
			if (to >= middle) paint.arc(cx, cy, radius, middle, to, weight, theme.accent);
			else paint.arc(cx, cy, radius, to, middle, weight, theme.accent);
		} else {
			paint.arc(cx, cy, radius, BEGAN, BEGAN + SWEEP * share(), weight, theme.accent);
		}

		final angle = BEGAN + SWEEP * share();
		final inner = radius - weight - metrics.whole(2);
		paint.line(cx + Math.cos(angle) * inner * 0.35, cy + Math.sin(angle) * inner * 0.35,
			cx + Math.cos(angle) * inner, cy + Math.sin(angle) * inner, metrics.whole(2),
			dragging || root.focus == this ? theme.ink : theme.dim);

		if (label != "" && small != null) {
			paint.reface(small);
			paint.textCentred(label, cx, y + height - small.descent, theme.dim);
		}
	}
}
