package mdd.ui;

@:unreflective

/**
	A widget whose contents are taller than it is, with a bar down the side.

	There is no bar along the bottom. Nothing here has ever needed one, and the panel
	that scrolls sideways carries its own, because its bar sits above the lanes rather
	than under them.
**/
class Scroll extends Widget {
	/**
		How far down the contents are scrolled.
	**/
	public var offsetY(default, null):Float = 0;

	/**
		How tall the contents are.
	**/
	public var contentHeight:Float = 0;

	var scrubbing:Bool = false;
	var grabAt:Float = 0;
	var grabOffset:Float = 0;

	/**
		Builds an empty scroller.
	**/
	public function new() {
		super();
		opaque = true;
	}

	/**
		@return Whether the contents are taller than the room for them.
	**/
	inline function downwards():Bool {
		return contentHeight > height + 0.5;
	}

	/**
		Scrolls down to a position, clamped to the contents.

		@param y How far down to scroll.
	**/
	public function scrollTo(y:Float):Void {
		var next = y;
		final most = contentHeight - height;

		if (next > most) next = most;
		if (next < 0) next = 0;

		if (next == offsetY) return;
		offsetY = next;
		invalidate();
	}

	/**
		@return How wide the bar is.
	**/
	public function thickness():Float {
		final root = root();
		return root == null ? 8 : root.metrics.whole(8);
	}

	/**
		@return How long the thumb is, from how much of the contents is visible.
	**/
	public function thumb():Float {
		if (!downwards()) return height;
		final share = height / contentHeight;
		final want = height * share;
		final least = thickness() * 3;
		return want < least ? least : want;
	}

	/**
		@return Where the thumb sits.
	**/
	public function thumbAt():Float {
		final travel = height - thumb();
		final most = contentHeight - height;
		return most <= 0 ? y : y + travel * (offsetY / most);
	}

	/**
		Puts the thumb under a press that landed on the track rather than on it,
		which is what a press below the thumb is asking for. Without this a press
		on the empty part of the bar did nothing at all until the pointer moved.

		@param py Where the press was, down.
		@param long How long the thumb is.
	**/
	function jumps(py:Float, long:Float):Void {
		final travel = height - long;
		final most = contentHeight - height;

		if (travel <= 0 || most <= 0) return;

		scrollTo((py - y - long * 0.5) / travel * most);
	}

	/**
		Scrolls on the wheel, and drags the thumb.

		@param event The event.
		@return Whether it was taken.
	**/
	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.Wheel:
				final root = root();
				final step = root == null ? 30 : root.metrics.row;

				if (!downwards()) return false;
				scrollTo(offsetY - event.dy * step);
				return true;

			case Kind.PointerDown:
				if (!downwards() || event.button != Pointer.Left) return false;

				final bar = x + width - thickness();
				if (event.x < bar) return false;

				final top = thumbAt();
				final long = thumb();

				if (event.y < top || event.y >= top + long) jumps(event.y, long);

				scrubbing = true;
				grabAt = event.y;
				grabOffset = offsetY;
				return true;

			case Kind.PointerMove:
				if (!scrubbing) return false;

				final travel = height - thumb();
				if (travel <= 0) return true;

				final most = contentHeight - height;
				scrollTo(grabOffset + (event.y - grabAt) * most / travel);
				return true;

			case Kind.PointerUp:
				if (!scrubbing) return false;
				scrubbing = false;
				return true;

			case _:
		}
		return false;
	}

	/**
		Finds what is under a point, taking the scroll offset into account and keeping
		a hit on the bar for itself.

		@param px A point, across.
		@param py A point, down.
		@return The widget there, or null.
	**/
	override function hit(px:Float, py:Float):Null<Widget> {
		if (!accepts(px, py)) return null;

		if (downwards() && px >= x + width - thickness()) return this;

		var found:Null<Widget> = null;
		var i = children.length - 1;

		while (i >= 0) {
			final child = children[i];
			if (child.visible) {
				final deeper = child.hit(px, py + offsetY);
				if (deeper != null) {
					found = deeper;
					break;
				}
			}
			i--;
		}

		return found != null ? found : this;
	}

	/**
		Draws the contents clipped and offset, then the bar.

		@param paint What to draw with.
	**/
	override function paint(paint:Paint):Void {
		paint.pushClip(x, y, width, height);
		paint.pushTransform(0, -offsetY);

		for (child in children) {
			if (child.visible) child.paint(paint);
		}

		paint.popTransform();
		paint.popClip();

		bar(paint);
	}

	/**
		Draws the bar, where the contents need one.

		@param paint What to draw with.
	**/
	function bar(paint:Paint):Void {
		if (!downwards()) return;

		final root = root();
		if (root == null) return;

		final theme = root.theme;
		final thick = thickness();
		final trackX = x + width - thick;

		paint.rect(trackX, y, thick, height, theme.sink, 0.6);
		paint.roundedRect(trackX + 1, thumbAt(), thick - 2, thumb(), (thick - 2) * 0.5,
			scrubbing ? theme.accent : theme.frame);
	}
}
