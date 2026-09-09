package mdd.ui;

@:unreflective

/**
	The draggable line between two panes.
**/
final class Splitter extends Widget {
	/**
		Whether the line is vertical, so it splits left from right.
	**/
	public var vertical:Bool = false;

	/**
		Where the line sits.
	**/
	public var position(default, null):Float = 0;

	/**
		The smallest the first pane may be dragged to.
	**/
	public var least:Float = 60;

	/**
		The largest.
	**/
	public var most:Float = 1e9;

	var onMove:Null<Splitter -> Void> = null;

	var dragging:Bool = false;
	var grabAt:Float = 0;
	var grabPosition:Float = 0;

	/**
		Builds a splitter.

		@param position Where the line starts.
	**/
	public function new(position:Float) {
		super();
		this.position = position;
	}

	/**
		Moves the line, held between the two limits.

		@param next Where to move it to.
	**/
	public function place(next:Float):Void {
		var held = next;
		if (held < least) held = least;
		if (held > most) held = most;

		if (held == position) return;
		position = held;
		if (onMove != null) onMove(this);
		relayout();
	}

	/**
		Drags the line.

		@param event The event.
		@return Whether it was taken.
	**/
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

	/**
		Draws the line, brighter while it is hovered or dragged.

		@param paint What to draw with.
	**/
	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null) return;

		final theme = root.theme;
		paint.rect(x, y, width, height,
			dragging || root.over == this ? theme.accent : theme.frame);
	}
}
