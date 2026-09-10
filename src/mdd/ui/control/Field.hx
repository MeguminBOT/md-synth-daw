package mdd.ui.control;

@:unreflective

/**
	A single line of editable text, with a caret, a selection and the four editing
	commands.

	It keeps its plain keys while a modified chord still reaches past it, which is what
	lets playback be stopped while a track is being renamed and a typed space not start
	it.
**/
final class Field extends Widget {
	/**
		What is in it.
	**/
	public var value(default, null):String = "";
	var caret(default, null):Int = 0;

	/**
		What is drawn when it is empty.
	**/
	public var hint:String = "";

	/**
		Where the selection started. The caret is the other end of it.
	**/
	public var mark(default, null):Int = 0;

	/**
		Called on every change, for something that follows as it is typed.
	**/
	public var onChange:Null<String -> Void> = null;

	/**
		Called when enter is pressed or the keyboard leaves.
	**/
	public var onCommit:Null<String -> Void> = null;

	/**
		What cut and copy write to and paste reads from.
	**/
	public var clipboard:String = "";

	var dragging:Bool = false;

	/**
		Builds a field.

		@param value What to start with.
	**/
	public function new(value:String = "") {
		super();
		focusable = true;
		typing = true;
		opaque = true;
		set(value);
	}

	/**
		Replaces the whole contents and puts the caret at the end.

		@param next The new contents.
	**/
	public function set(next:String):Void {
		value = next;
		caret = next.length;
		mark = caret;
		invalidate();
	}

	inline function selecting():Bool {
		return caret != mark;
	}

	/**
		@return Where the selection starts.
	**/
	public inline function from():Int {
		return caret < mark ? caret : mark;
	}

	/**
		@return Where it ends.
	**/
	public inline function to():Int {
		return caret < mark ? mark : caret;
	}

	/**
		@return The selected text, or an empty string.
	**/
	public function selected():String {
		return selecting() ? value.substring(from(), to()) : "";
	}

	/**
		Moves the caret.

		@param at Where to put it.
		@param keep Whether to keep the selection, which is what shift does.
	**/
	function place(at:Int, keep:Bool):Void {
		var next = at;
		if (next < 0) next = 0;
		if (next > value.length) next = value.length;

		caret = next;
		if (!keep) mark = next;
		invalidate();
	}

	/**
		Removes the selection.

		@return Whether there was one.
	**/
	function drop():Bool {
		if (!selecting()) return false;

		final start = from();
		value = value.substring(0, start) + value.substring(to());
		caret = start;
		mark = start;
		changed();
		return true;
	}

	/**
		Puts text in over the selection.

		@param text What to put in.
	**/
	function put(text:String):Void {
		drop();
		value = value.substring(0, caret) + text + value.substring(caret);
		caret += text.length;
		mark = caret;
		changed();
	}

	/**
		Tells `onChange` and asks for a redraw.
	**/
	function changed():Void {
		invalidate();
		if (onChange != null) onChange(value);
	}

	/**
		A field takes typing, which an I-beam is how a reader is told.

		@param px A point, across.
		@param py A point, down.
		@return Which cursor shape belongs there.
	**/
	override function cursorAt(px:Float, py:Float):Int {
		return mdd.host.Sdl.CURSOR_TEXT;
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				if (event.button != Pointer.Left) return false;
				dragging = true;

				if (event.clicks >= 2) {
					mark = 0;
					caret = value.length;
					invalidate();
				} else {
					place(index(event.x), event.shift());
				}
				return true;

			case Kind.PointerMove:
				if (!dragging) return false;
				place(index(event.x), true);
				return true;

			case Kind.PointerUp:
				if (!dragging) return false;
				dragging = false;
				return true;

			case Kind.Text:
				put(event.said);
				return true;

			case Kind.KeyDown:
				return pressed(event);

			case _:
		}
		return false;
	}

	/**
		Handles a pointer press: places the caret, and selects a word or everything on
		a second or third click.

		@param event The event.
		@return Whether it was taken.
	**/
	function pressed(event:Input):Bool {
		final keep = event.shift();

		if (event.ctrl()) {
			switch (event.code) {
				case Key.A:
					mark = 0;
					caret = value.length;
					invalidate();
					return true;

				case Key.C:
					if (selecting()) clipboard = selected();
					return true;

				case Key.X:
					if (selecting()) {
						clipboard = selected();
						drop();
					}
					return true;

				case Key.V:
					if (clipboard != "") put(clipboard);
					return true;

				case _:
			}
		}

		switch (event.code) {
			case Key.Left:
				place(caret - 1, keep);
				return true;

			case Key.Right:
				place(caret + 1, keep);
				return true;

			case Key.Home:
				place(0, keep);
				return true;

			case Key.End:
				place(value.length, keep);
				return true;

			case Key.Backspace:
				if (!drop() && caret > 0) {
					value = value.substring(0, caret - 1) + value.substring(caret);
					caret--;
					mark = caret;
					changed();
				}
				return true;

			case Key.Delete:
				if (!drop() && caret < value.length) {
					value = value.substring(0, caret) + value.substring(caret + 1);
					changed();
				}
				return true;

			case Key.Return:
				if (onCommit != null) onCommit(value);
				return true;

			case Key.Escape:
				mark = caret;
				invalidate();
				return true;

			case _:
		}

		return false;
	}

	/**
		@param px A point, across.
		@return Which character is there.
	**/
	function index(px:Float):Int {
		final root = root();
		if (root == null || root.metrics.mono == null) return value.length;

		final font = root.metrics.mono;
		final left = x + root.metrics.unit * 2;

		var pen = left;
		var index = 0;

		while (index < value.length) {
			final code = Font.codeAt(value, index);
			final next = index + Font.step(code);
			final slot = font.slotOf(code);

			if (slot != Font.NONE) {
				final held = font.advance(slot);
				if (px < pen + held * 0.5) return index;

				pen += held;
			}

			index = next;
		}

		return value.length;
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final font = metrics.mono;
		if (font == null) return;

		paint.roundedRect(x, y, width, height, metrics.radiusRow, theme.sink);
		paint.reface(font);

		final left = x + metrics.unit * 2;
		final baseline = y + (height - font.height) * 0.5 + font.ascent;

		if (selecting()) {
			final start = left + font.measure(value.substring(0, from()));
			final stop = left + font.measure(value.substring(0, to()));
			paint.rect(start, y + metrics.unit, stop - start, height - metrics.unit * 2,
				theme.accent, Theme.SELECT);
		}

		if (value == "" && hint != "" && root.focus != this) {
			paint.text(hint, left, baseline, theme.dim, 0.5);
		} else paint.text(value, left, baseline, theme.ink);

		if (root.focus == this) {
			final at = left + font.measure(value.substring(0, caret));
			paint.rect(at, y + metrics.unit, metrics.whole(1), height - metrics.unit * 2, theme.ink);
			paint.outline(x, y, width, height, theme.accent, metrics.whole(1), 1,
				metrics.radiusRow);
		} else {
			paint.outline(x, y, width, height, theme.frame, metrics.whole(1), 1,
				metrics.radiusRow);
		}
	}
}
