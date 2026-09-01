package mdd.ui;

@:unreflective
final class Field extends Widget {
	public var value(default, null):String = "";
	public var caret(default, null):Int = 0;
	public var mark(default, null):Int = 0;

	public var onChange:Null<String -> Void> = null;
	public var onCommit:Null<String -> Void> = null;

	public var clipboard:String = "";

	var dragging:Bool = false;

	public function new(value:String = "") {
		super();
		focusable = true;
		opaque = true;
		set(value);
	}

	public function set(next:String):Void {
		value = next;
		caret = next.length;
		mark = caret;
		invalidate();
	}

	public inline function selecting():Bool {
		return caret != mark;
	}

	public inline function from():Int {
		return caret < mark ? caret : mark;
	}

	public inline function to():Int {
		return caret < mark ? mark : caret;
	}

	public function selected():String {
		return selecting() ? value.substring(from(), to()) : "";
	}

	function place(at:Int, keep:Bool):Void {
		var next = at;
		if (next < 0) next = 0;
		if (next > value.length) next = value.length;

		caret = next;
		if (!keep) mark = next;
		invalidate();
	}

	function drop():Bool {
		if (!selecting()) return false;

		final start = from();
		value = value.substring(0, start) + value.substring(to());
		caret = start;
		mark = start;
		changed();
		return true;
	}

	function put(text:String):Void {
		drop();
		value = value.substring(0, caret) + text + value.substring(caret);
		caret += text.length;
		mark = caret;
		changed();
	}

	function changed():Void {
		invalidate();
		if (onChange != null) onChange(value);
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

	function index(px:Float):Int {
		final root = root();
		if (root == null || root.metrics.mono == null) return value.length;

		final font = root.metrics.mono;
		final left = x + root.metrics.unit * 2;

		var pen = left;
		for (i in 0...value.length) {
			final code = value.charCodeAt(i);
			if (!font.has(code)) continue;

			final step = font.advance(code);
			if (px < pen + step * 0.5) return i;
			pen += step;
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

		paint.text(value, left, baseline, theme.ink);

		if (root.focus == this) {
			final at = left + font.measure(value.substring(0, caret));
			paint.rect(at, y + metrics.unit, metrics.whole(1), height - metrics.unit * 2, theme.ink);
			paint.outline(x, y, width, height, theme.accent, metrics.whole(1));
		} else {
			paint.outline(x, y, width, height, theme.frame, metrics.whole(1));
		}
	}
}
