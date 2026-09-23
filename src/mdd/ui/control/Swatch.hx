package mdd.ui.control;

@:unreflective

/**
	A square of one colour that is clicked to change it. It opens nothing itself: `onFire` is where
	whatever changes the colour is opened, and `onClear` is what a right click asks for, such as
	going back to a colour the swatch is not holding one of its own for.
**/
final class Swatch extends Widget {
	/**
		The colour shown, as `0xRRGGBB`.
	**/
	public var colour:Int = 0x000000;

	/**
		Whether the colour shown is one the swatch is standing in for rather than one chosen for
		it, which draws a slash across it.
	**/
	public var borrowed:Bool = false;

	/**
		Called when it is clicked.
	**/
	public var onFire:Null<Swatch -> Void> = null;

	/**
		Called when it is right clicked, or null where a right click does nothing.
	**/
	public var onClear:Null<Swatch -> Void> = null;

	/**
		Builds a swatch.

		@param colour The colour it starts showing, as `0xRRGGBB`.
	**/
	public function new(colour:Int) {
		super();
		this.colour = colour;
		focusable = true;
		opaque = true;
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				if (event.button == Pointer.Right) {
					if (onClear == null) return false;

					onClear(this);
					return true;
				}

				if (event.button != Pointer.Left || onFire == null) return false;

				onFire(this);
				return true;

			case Kind.KeyDown:
				if (!event.plain()) return false;
				if (event.code != Key.Space && event.code != Key.Return) return false;
				if (onFire == null) return false;

				onFire(this);
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
		final hair = metrics.whole(1);

		paint.roundedRect(x, y, width, height, metrics.radiusSmall, colour);

		if (borrowed) {
			paint.line(x + width - hair * 3, y + hair * 3, x + hair * 3, y + height - hair * 3,
				metrics.whole(1.5), theme.ground, 0.8);
		}

		paint.outline(x, y, width, height, root.focus == this || root.over == this ? theme.accent : theme.frame,
			hair, 1, metrics.radiusSmall);
	}
}
