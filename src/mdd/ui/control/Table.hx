package mdd.ui.control;

typedef Cell = (row:Int, column:Int) -> String;

@:unreflective
final class Table extends Scroll {
	public var rows(default, null):Int = 0;
	public var columns(default, null):Int = 0;

	public final widths:Array<Float> = [];
	final headings:Array<String> = [];

	public var read:Null<Cell> = null;
	public var tint:Null<Int -> Colour> = null;

	public var chosen(default, null):Int = -1;
	public var onChoose:Null<Int -> Void> = null;

	public var painted(default, null):Int = 0;
	public var rowHeight:Float = 0;

	public function new(columns:Int) {
		super();
		this.columns = columns;
		focusable = true;

		for (i in 0...columns) {
			widths.push(0);
			headings.push("");
		}
	}

	public function hold(rows:Int):Void {
		this.rows = rows;
		contentHeight = rows * step();
		invalidate();
	}

	inline function step():Float {
		if (rowHeight > 0) return rowHeight;
		final root = root();
		return root == null ? 18 : root.metrics.whole(18);
	}

	public function choose(row:Int):Void {
		if (row < 0 || row >= rows || row == chosen) return;
		chosen = row;
		invalidate();
		if (onChoose != null) onChoose(row);
	}

	public function rowAt(py:Float):Int {
		final at = Std.int((py - y + offsetY) / step());
		return at < 0 || at >= rows ? -1 : at;
	}

	override function took(event:Input):Bool {
		if (super.took(event)) return true;

		switch (event.kind) {
			case Kind.PointerDown:
				final row = rowAt(event.y);
				if (row < 0) return false;
				choose(row);
				return true;

			case Kind.KeyDown:
				switch (event.code) {
					case Key.Up:
						choose(chosen - 1);
						reveal();
						return true;
					case Key.Down:
						choose(chosen + 1);
						reveal();
						return true;
					case Key.Home:
						choose(0);
						scrollTo(0);
						return true;
					case Key.End:
						choose(rows - 1);
						scrollTo(contentHeight);
						return true;
					case _:
				}

			case _:
		}
		return false;
	}

	function reveal():Void {
		if (chosen < 0) return;

		final tall = step();
		final top = chosen * tall;

		if (top < offsetY) scrollTo(top);
		else if (top + tall > offsetY + height) scrollTo(top + tall - height);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.mono == null || read == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final font = metrics.mono;
		final tall = step();

		paint.pushClip(x, y, width, height);
		paint.reface(font);

		var first = Std.int(offsetY / tall);
		if (first < 0) first = 0;

		var last = Std.int((offsetY + height) / tall) + 1;
		if (last > rows) last = rows;

		painted = last - first;

		for (row in first...last) {
			final top = y + row * tall - offsetY;

			if (row == chosen) {
				paint.rect(x, top, width, tall, theme.accent, Theme.SELECT);
			} else if ((row & 3) == 0) {
				paint.rect(x, top, width, tall, theme.ink, 0.022);
			}

			final ink = tint != null ? tint(row) : theme.ink;
			var pen = x + metrics.unit * 2;

			for (column in 0...columns) {
				paint.text(read(row, column), pen, top + (tall - font.height) * 0.5 + font.ascent,
					column == 0 ? theme.dim : ink);
				pen += widths[column];
			}
		}

		paint.popClip();
		bar(paint);
	}
}
