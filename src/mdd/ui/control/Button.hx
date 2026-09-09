package mdd.ui.control;

@:unreflective

/**
	A button, which can also be a latch that stays down.
**/
final class Button extends Widget {
	/**
		What it says.
	**/
	public var label:String;

	/**
		Whether the pointer is down on it.
	**/
	public var pressed(default, null):Bool = false;

	/**
		Whether it is drawn pressed, which a latch stays.
	**/
	public var down(default, null):Bool = false;

	/**
		Whether it latches rather than springing back.
	**/
	public var toggle:Bool = false;

	/**
		Whether a latch is on.
	**/
	public var on:Bool = false;

	/**
		What to do when it is pressed.
	**/
	public var onFire:Null<Button -> Void> = null;

	var inside:Bool = false;

	/**
		Builds a button.

		@param label What it says.
	**/
	public function new(label:String) {
		super();
		this.label = label;
		focusable = true;
		opaque = true;
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				if (event.button != Pointer.Left || !enabled) return false;

				down = true;
				inside = true;
				invalidate();

				if (toggle) {
					on = !on;
					fire();
				}
				return true;

			case Kind.PointerMove:
				if (!down) return false;

				final was = inside;
				inside = holds(event.x, event.y);
				if (was != inside) invalidate();
				return true;

			case Kind.PointerUp:
				if (!down) return false;

				down = false;
				invalidate();

				if (inside && !toggle) fire();
				return true;

			case Kind.KeyDown:
				if (!event.plain()) return false;
				if (event.code != Key.Space && event.code != Key.Return) return false;

				if (toggle) on = !on;
				fire();
				return true;

			case _:
		}
		return false;
	}

	/**
		Flips a latch and calls `onFire`.
	**/
	function fire():Void {
		pressed = true;
		invalidate();
		if (onFire != null) onFire(this);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final font = metrics.body;
		if (font == null) return;

		paint.roundedRect(x, y, width, height, metrics.radiusRow, theme.raise1);

		if (on) {
			paint.roundedRect(x, y, width, height, metrics.radiusRow, theme.accent, Theme.SELECT);
		}
		if (down && inside) {
			paint.roundedRect(x, y, width, height, metrics.radiusRow, theme.accent, Theme.PRESS);
		} else if (root.over == this && enabled) {
			paint.roundedRect(x, y, width, height, metrics.radiusRow, theme.accent, Theme.HOVER);
		}

		paint.outline(x, y, width, height, root.focus == this ? theme.accent : theme.frame,
			metrics.whole(1), 1, metrics.radiusRow);

		paint.reface(font);
		final ink = enabled ? (on ? theme.ink : theme.dim) : theme.dim;
		paint.textCentred(label, x + width * 0.5, y + (height - font.height) * 0.5 + font.ascent,
			ink, enabled ? 1 : 0.5);
	}
}
