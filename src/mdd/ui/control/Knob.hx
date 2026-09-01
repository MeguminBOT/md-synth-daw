package mdd.ui.control;

@:unreflective
final class Knob extends Widget implements Range {
	static inline final TRAVEL = 128.0;
	static inline final SWEEP = 4.712389;
	static inline final BEGAN = 2.356194;

	public var value(get, never):Int;

	var carried:Int = 0;
	public var least(default, null):Int = 0;
	public var most(default, null):Int = 127;

	public var label:String = "";
	public var centred:Bool = false;
	public var onChange:Null<Knob -> Void> = null;

	var dragging:Bool = false;
	var grabY:Float = 0;
	var grabValue:Int = 0;
	var fine:Bool = false;

	public function new(label:String, value:Int, least:Int, most:Int) {
		super();
		this.label = label;
		this.least = least;
		this.most = most;
		focusable = true;
		opaque = true;
		carried = least - 1;
		set(value);
	}

	public inline function span():Int {
		return most - least;
	}

	public function share():Float {
		final run = span();
		return run == 0 ? 0 : (carried - least) / run;
	}

	function get_value():Int {
		return carried;
	}

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
				fine = event.ctrl();
				return true;

			case Kind.PointerMove:
				if (!dragging) return false;
				final moved = (grabY - event.y) / (fine ? TRAVEL * 4 : TRAVEL);
				set(grabValue + Math.round(moved * span()));
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
