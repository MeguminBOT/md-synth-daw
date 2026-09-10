package mdd.ui.control;

@:unreflective

/**
	A slider: a value in a range, dragged along a track.
**/
final class Slider extends Widget implements Range {
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
		Whether the track runs up rather than across.
	**/
	public var vertical:Bool = false;

	/**
		Called when the value changes.
	**/
	public var onChange:Null<Slider -> Void> = null;

	var dragging:Bool = false;

	/**
		Builds a slider.

		@param value Where it starts.
		@param least The smallest it goes.
		@param most The largest.
	**/
	public function new(value:Int, least:Int, most:Int) {
		super();
		this.least = least;
		this.most = most;
		focusable = true;
		opaque = true;
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
		@return How wide the grip draws, which is also how much of the track it
			takes away from the travel.
	**/
	public function grip():Float {
		final root = root();
		return root == null ? 11 : root.metrics.whole(11);
	}

	/**
		Moves the value to wherever a point along the track is.

		The grip is measured from its middle over the travel the paint draws it
		across, not from the edge of the widget: mapping the whole width instead
		puts the grip somewhere other than the pointer, worst at either end, so
		taking hold of it moved it before the drag began.

		@param px A point, across.
		@param py A point, down.
	**/
	function reach(px:Float, py:Float):Void {
		final held = grip();
		final travel = (vertical ? height : width) - held;

		if (travel <= 0) return;

		final along = vertical
			? 1 - (py - y - held * 0.5) / travel
			: (px - x - held * 0.5) / travel;

		final want = along < 0 ? 0.0 : (along > 1 ? 1.0 : along);
		set(least + Math.round(want * span()));
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
		final grip = grip();

		if (vertical) {
			final trackX = x + (width - thick) * 0.5;
			paint.roundedRect(trackX, y, thick, height, thick * 0.5, theme.sink);

			final travel = height - grip;
			final at = y + travel * (1 - share());
			paint.roundedGradient(trackX, at, thick, height - (at - y), thick * 0.5,
				theme.accent.lift(0.20), theme.accent.sink(0.16));
			paint.roundedRect(x, at, width, grip, metrics.radiusSmall, theme.raise2);
			paint.outline(x, at, width, grip, theme.frame, metrics.whole(1), 1,
				metrics.radiusSmall);
		} else {
			final trackY = y + (height - thick) * 0.5;
			paint.roundedRect(x, trackY, width, thick, thick * 0.5, theme.sink);
			paint.roundedGradient(x, trackY, width * share(), thick, thick * 0.5,
				theme.accent.lift(0.20), theme.accent.sink(0.16));

			final at = x + (width - grip) * share();
			paint.roundedRect(at, y, grip, height, metrics.radiusSmall, theme.raise2);
			paint.outline(at, y, grip, height, theme.frame, metrics.whole(1), 1,
				metrics.radiusSmall);
		}

		if (root.focus == this) {
			paint.outline(x, y, width, height, theme.accent, metrics.whole(1));
		}
	}
}
