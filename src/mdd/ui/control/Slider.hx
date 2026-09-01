package mdd.ui.control;

@:unreflective
final class Slider extends Widget implements Range {
	public var value(get, never):Int;

	var carried:Int = 0;
	public var least(default, null):Int = 0;
	public var most(default, null):Int = 127;

	public var vertical:Bool = false;
	public var onChange:Null<Slider -> Void> = null;

	var dragging:Bool = false;

	public function new(value:Int, least:Int, most:Int) {
		super();
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

	function reach(px:Float, py:Float):Void {
		final along = vertical ? 1 - (py - y) / height : (px - x) / width;
		set(least + Math.round(along * span()));
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				if (event.button != Pointer.Left) return false;
				dragging = true;
				reach(event.x, event.y);
				return true;

			case Kind.PointerMove:
				if (!dragging) return false;
				reach(event.x, event.y);
				return true;

			case Kind.PointerUp:
				if (!dragging) return false;
				dragging = false;
				return true;

			case Kind.Wheel:
				set(carried + Std.int(event.dy) * (event.ctrl() ? 1 : 4));
				return true;

			case Kind.KeyDown:
				final step = event.ctrl() ? 1 : 4;
				switch (event.code) {
					case Key.Left, Key.Down:
						set(carried - step);
						return true;
					case Key.Right, Key.Up:
						set(carried + step);
						return true;
					case Key.Home:
						set(least);
						return true;
					case Key.End:
						set(most);
						return true;
					case _:
				}

			case _:
		}
		return false;
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final thick = metrics.whole(6);
		final grip = metrics.whole(11);

		if (vertical) {
			final trackX = x + (width - thick) * 0.5;
			paint.roundedRect(trackX, y, thick, height, thick * 0.5, theme.sink);

			final travel = height - grip;
			final at = y + travel * (1 - share());
			paint.roundedRect(trackX, at, thick, height - (at - y), thick * 0.5, theme.accent);
			paint.roundedRect(x, at, width, grip, metrics.radiusSmall, theme.raise2);
			paint.outline(x, at, width, grip, theme.frame, metrics.whole(1));
		} else {
			final trackY = y + (height - thick) * 0.5;
			paint.roundedRect(x, trackY, width, thick, thick * 0.5, theme.sink);
			paint.roundedRect(x, trackY, width * share(), thick, thick * 0.5, theme.accent);

			final at = x + (width - grip) * share();
			paint.roundedRect(at, y, grip, height, metrics.radiusSmall, theme.raise2);
			paint.outline(at, y, grip, height, theme.frame, metrics.whole(1));
		}

		if (root.focus == this) {
			paint.outline(x, y, width, height, theme.accent, metrics.whole(1));
		}
	}
}
