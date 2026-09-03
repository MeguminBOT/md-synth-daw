package mdd.ui.control;

@:unreflective
final class Number extends Widget implements Range {
	public var label:String;
	public var unit:String = "";

	public var value(get, never):Int;

	var carried:Int = 0;
	public var least(default, null):Int = 0;
	public var most(default, null):Int = 127;

	public var onChange:Null<Number -> Void> = null;
	public var derived:Null<Int -> String> = null;

	var dragging:Bool = false;
	var grabY:Float = 0;
	var grabValue:Int = 0;
	var fine:Bool = false;

	var entry:String = "";

	public function new(label:String, value:Int, least:Int, most:Int) {
		super();
		this.label = label;
		this.least = least;
		this.most = most;
		focusable = true;
		opaque = true;
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

	public function fits():Float {
		final root = root();
		if (root == null) return 70;

		final metrics = root.metrics;
		final mono = metrics.mono;
		final small = metrics.small;

		if (mono == null || small == null) return 70;

		final said = derived != null ? derived(value) : Std.string(value);
		final wide = small.measure(label) + mono.measure(said) + metrics.unit * 6;
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
			root.focus == this || dragging ? theme.accent : theme.frame, metrics.whole(1));

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
