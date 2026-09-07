package mdd.ui;

@:unreflective
class Scroll extends Widget {
	public var offsetY(default, null):Float = 0;
	public var offsetX(default, null):Float = 0;

	public var contentHeight:Float = 0;
	public var contentWidth:Float = 0;

	public var sideways:Bool = false;

	var scrubbing:Bool = false;
	var grabAt:Float = 0;
	var grabOffset:Float = 0;

	public function new() {
		super();
		opaque = true;
	}

	inline function downwards():Bool {
		return contentHeight > height + 0.5;
	}

	public inline function across():Bool {
		return sideways && contentWidth > width + 0.5;
	}

	public function scrollTo(y:Float):Void {
		var next = y;
		final most = contentHeight - height;

		if (next > most) next = most;
		if (next < 0) next = 0;

		if (next == offsetY) return;
		offsetY = next;
		invalidate();
	}

	function scrollAcross(x:Float):Void {
		var next = x;
		final most = contentWidth - width;

		if (next > most) next = most;
		if (next < 0) next = 0;

		if (next == offsetX) return;
		offsetX = next;
		invalidate();
	}

	function thickness():Float {
		final root = root();
		return root == null ? 8 : root.metrics.whole(8);
	}

	function thumb():Float {
		if (!downwards()) return height;
		final share = height / contentHeight;
		final want = height * share;
		final least = thickness() * 3;
		return want < least ? least : want;
	}

	function thumbAt():Float {
		final travel = height - thumb();
		final most = contentHeight - height;
		return most <= 0 ? y : y + travel * (offsetY / most);
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.Wheel:
				final root = root();
				final step = root == null ? 30 : root.metrics.row;

				if (event.shift() && across()) {
					scrollAcross(offsetX - event.dy * step);
					return true;
				}

				if (!downwards()) return false;
				scrollTo(offsetY - event.dy * step);
				return true;

			case Kind.PointerDown:
				if (!downwards() || event.button != Pointer.Left) return false;

				final bar = x + width - thickness();
				if (event.x < bar) return false;

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

	override function hit(px:Float, py:Float):Null<Widget> {
		if (!accepts(px, py)) return null;

		if (downwards() && px >= x + width - thickness()) return this;

		var found:Null<Widget> = null;
		var i = children.length - 1;

		while (i >= 0) {
			final child = children[i];
			if (child.visible) {
				final deeper = child.hit(px + offsetX, py + offsetY);
				if (deeper != null) {
					found = deeper;
					break;
				}
			}
			i--;
		}

		return found != null ? found : this;
	}

	override function paint(paint:Paint):Void {
		paint.pushClip(x, y, width, height);
		paint.pushTransform(-offsetX, -offsetY);

		for (child in children) {
			if (child.visible) child.paint(paint);
		}

		paint.popTransform();
		paint.popClip();

		bar(paint);
	}

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
