package mdd.ui;

import haxe.ds.Vector;

@:unreflective
final class Tree extends Scroll {
	public final roots:Array<Item> = [];

	public var chosen(default, null):Null<Item> = null;
	public var onChoose:Null<Item -> Void> = null;
	public var onOpen:Null<Item -> Void> = null;

	public var painted(default, null):Int = 0;
	public var rowHeight:Float = 0;

	final shown:Array<Item> = [];
	final arrow:Vector<Float> = new Vector<Float>(6);
	var hoverAt:Int = -1;

	public function new() {
		super();
		focusable = true;
	}

	public function plant(item:Item):Item {
		roots.push(item);
		reflow();
		return item;
	}

	public function clear():Void {
		roots.resize(0);
		chosen = null;
		reflow();
	}

	public inline function rows():Int {
		return shown.length;
	}

	public function shownAt(index:Int):Null<Item> {
		return index < 0 || index >= shown.length ? null : shown[index];
	}

	public function reflow():Void {
		shown.resize(0);
		for (item in roots) gather(item);

		contentHeight = shown.length * step();
		invalidate();
	}

	function gather(item:Item):Void {
		shown.push(item);
		if (!item.open) return;
		for (child in item.children) gather(child);
	}

	inline function step():Float {
		if (rowHeight > 0) return rowHeight;
		final root = root();
		return root == null ? 22 : root.metrics.whole(22);
	}

	public function fold(item:Item, open:Bool):Void {
		if (!item.branch() || item.open == open) return;
		item.open = open;
		reflow();
		if (onOpen != null) onOpen(item);
	}

	public function select(item:Null<Item>):Bool {
		if (item == chosen || (item != null && !item.enabled)) return false;
		chosen = item;
		invalidate();
		return true;
	}

	public function choose(item:Null<Item>):Void {
		if (!select(item)) return;
		if (chosen != null && onChoose != null) onChoose(chosen);
	}

	public function rowAt(py:Float):Int {
		final at = Std.int((py - y + offsetY) / step());
		return at < 0 || at >= shown.length ? -1 : at;
	}

	inline function indent(metrics:Metrics, item:Item):Float {
		return metrics.inset + item.depth * metrics.whole(14);
	}

	function onChevron(metrics:Metrics, item:Item, px:Float):Bool {
		final left = x + indent(metrics, item) - metrics.whole(12);
		return px >= left && px < left + metrics.whole(14);
	}

	override function took(event:Input):Bool {
		if (super.took(event)) return true;

		final root = root();
		if (root == null) return false;

		switch (event.kind) {
			case Kind.PointerDown:
				if (event.button != Pointer.Left) return false;

				final at = rowAt(event.y);
				if (at < 0) return false;

				final item = shown[at];

				if (item.branch() && (onChevron(root.metrics, item, event.x) || event.clicks > 1)) {
					fold(item, !item.open);
					return true;
				}

				choose(item);
				return true;

			case Kind.PointerMove:
				final at = rowAt(event.y);
				if (at == hoverAt) return false;
				hoverAt = at;
				invalidate();
				return true;

			case Kind.KeyDown:
				return steered(event.code);

			case _:
		}
		return false;
	}

	function steered(code:Key):Bool {
		final at = chosen == null ? -1 : shown.indexOf(chosen);

		switch (code) {
			case Key.Up:
				if (at > 0) choose(shown[at - 1]);
				reveal();
				return true;

			case Key.Down:
				if (at + 1 < shown.length) choose(shown[at + 1]);
				reveal();
				return true;

			case Key.Left:
				if (chosen == null) return false;
				if (chosen.branch() && chosen.open) fold(chosen, false);
				else if (chosen.parent != null) choose(chosen.parent);
				reveal();
				return true;

			case Key.Right:
				if (chosen == null) return false;
				if (chosen.branch() && !chosen.open) fold(chosen, true);
				else if (chosen.branch()) choose(chosen.children[0]);
				reveal();
				return true;

			case Key.Home:
				if (shown.length > 0) choose(shown[0]);
				scrollTo(0);
				return true;

			case Key.End:
				if (shown.length > 0) choose(shown[shown.length - 1]);
				scrollTo(contentHeight);
				return true;

			case _:
		}
		return false;
	}

	function reveal():Void {
		if (chosen == null) return;

		final at = shown.indexOf(chosen);
		if (at < 0) return;

		final tall = step();
		final top = at * tall;

		if (top < offsetY) scrollTo(top);
		else if (top + tall > offsetY + height) scrollTo(top + tall - height);
	}

	override function hovered(on:Bool):Void {
		if (!on) hoverAt = -1;
		super.hovered(on);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final font = metrics.body;
		final tall = step();

		paint.pushClip(x, y, width, height);
		paint.reface(font);

		var first = Std.int(offsetY / tall);
		if (first < 0) first = 0;

		var last = Std.int((offsetY + height) / tall) + 1;
		if (last > shown.length) last = shown.length;

		painted = last - first;

		for (at in first...last) {
			final item = shown[at];
			final top = y + at * tall - offsetY;
			final left = x + indent(metrics, item);
			final header = item.branch() && item.depth == 0;

			if (item == chosen) {
				paint.roundedRect(x + metrics.unit, top, width - metrics.unit * 2, tall,
					metrics.radiusSmall, theme.accent, Theme.SELECT);
			} else if (at == hoverAt) {
				paint.roundedRect(x + metrics.unit, top, width - metrics.unit * 2, tall,
					metrics.radiusSmall, theme.accent, Theme.HOVER);
			} else if (header) {
				paint.rect(x, top, width, tall, theme.raise1, 0.6);
			}

			if (item.branch()) chevron(paint, theme, metrics, item, left, top, tall);

			var pen = left;

			if (item.tint >= 0) {
				final dot = metrics.whole(6);
				paint.roundedRect(pen, top + (tall - dot) * 0.5, dot, dot, dot * 0.5, item.tint,
					item.enabled ? 1 : 0.4);
				pen += dot + metrics.unit * 2;
			}

			final ink = item == chosen || header ? theme.ink : theme.dim;
			paint.text(item.label, pen, top + (tall - font.height) * 0.5 + font.ascent, ink,
				item.enabled ? 1 : 0.45);
		}

		paint.popClip();
		bar(paint);
	}

	function chevron(paint:Paint, theme:Theme, metrics:Metrics, item:Item, left:Float, top:Float,
			tall:Float):Void {
		final size = metrics.whole(4);
		final cx = left - metrics.whole(12) + metrics.whole(7);
		final cy = top + tall * 0.5;

		if (item.open) {
			arrow[0] = cx - size;
			arrow[1] = cy - size * 0.5;
			arrow[2] = cx + size;
			arrow[3] = cy - size * 0.5;
			arrow[4] = cx;
			arrow[5] = cy + size * 0.7;
		} else {
			arrow[0] = cx - size * 0.5;
			arrow[1] = cy - size;
			arrow[2] = cx + size * 0.7;
			arrow[3] = cy;
			arrow[4] = cx - size * 0.5;
			arrow[5] = cy + size;
		}

		paint.polygon(arrow, 3, theme.dim);
	}
}
