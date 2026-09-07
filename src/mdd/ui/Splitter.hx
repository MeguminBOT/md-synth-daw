package mdd.ui;

@:unreflective
final class Splitter extends Widget {
	public var vertical:Bool = false;
	public var position(default, null):Float = 0;
	public var least:Float = 60;
	public var most:Float = 1e9;

	var onMove:Null<Splitter -> Void> = null;

	var dragging:Bool = false;
	var grabAt:Float = 0;
	var grabPosition:Float = 0;

	public function new(position:Float) {
		super();
		this.position = position;
	}

	public function place(next:Float):Void {
		var held = next;
		if (held < least) held = least;
		if (held > most) held = most;

		if (held == position) return;
		position = held;
		if (onMove != null) onMove(this);
		relayout();
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				if (event.button != Pointer.Left) return false;
				dragging = true;
				grabAt = vertical ? event.y : event.x;
				grabPosition = position;
				return true;

			case Kind.PointerMove:
				if (!dragging) return false;
				place(grabPosition + ((vertical ? event.y : event.x) - grabAt));
				return true;

			case Kind.PointerUp:
				if (!dragging) return false;
				dragging = false;
				return true;

			case _:
		}
		return false;
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null) return;

		final theme = root.theme;
		paint.rect(x, y, width, height,
			dragging || root.over == this ? theme.accent : theme.frame);
	}
}
