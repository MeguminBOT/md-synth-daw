package mdd.ui.control;

@:unreflective
final class Tabs extends Widget {
	public final labels:Array<String> = [];
	public var chosen(default, null):Int = 0;
	public var onChoose:Null<Int -> Void> = null;

	public var overflowed(default, null):Int = 0;

	var hoverAt:Int = -1;

	public function new(labels:Array<String>) {
		super();
		for (label in labels) this.labels.push(label);
		focusable = true;
		opaque = true;
	}

	public function choose(which:Int):Void {
		if (which < 0 || which >= labels.length || which == chosen) return;
		chosen = which;
		invalidate();
		if (onChoose != null) onChoose(which);
	}

	function widthOf(font:Font, metrics:Metrics, which:Int):Float {
		return font.measure(labels[which]) + metrics.inset * 2;
	}

	public function at(px:Float):Int {
		final root = root();
		if (root == null || root.metrics.body == null) return -1;

		final font = root.metrics.body;
		final metrics = root.metrics;

		var pen = x;
		for (i in 0...labels.length) {
			final wide = widthOf(font, metrics, i);
			if (pen + wide > x + width) return -1;
			if (px >= pen && px < pen + wide) return i;
			pen += wide;
		}
		return -1;
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				final which = at(event.x);
				if (which < 0) return false;
				choose(which);
				return true;

			case Kind.PointerMove:
				final which = at(event.x);
				if (which == hoverAt) return false;
				hoverAt = which;
				invalidate();
				return true;

			case Kind.KeyDown:
				switch (event.code) {
					case Key.Left:
						choose(chosen - 1);
						return true;
					case Key.Right:
						choose(chosen + 1);
						return true;
					case _:
				}

			case _:
		}
		return false;
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

		paint.rect(x, y, width, height, theme.bar);
		paint.reface(font);

		var pen = x;
		overflowed = 0;

		for (i in 0...labels.length) {
			final wide = widthOf(font, metrics, i);

			if (pen + wide > x + width) {
				overflowed = labels.length - i;
				paint.text("+" + overflowed, pen + metrics.unit, y + (height - font.height) * 0.5
					+ font.ascent, theme.dim);
				break;
			}

			final on = i == chosen;
			if (on) {
				paint.roundedRect(pen, y + metrics.whole(3), wide, height, metrics.radiusRow,
					theme.ground);
				paint.rect(pen + metrics.unit * 2, y + metrics.whole(3),
					wide - metrics.unit * 4, metrics.whole(2), theme.accent);
			} else if (i == hoverAt) {
				paint.roundedRect(pen, y + metrics.whole(3), wide, height, metrics.radiusRow,
					theme.accent, Theme.HOVER);
			}

			paint.textCentred(labels[i], pen + wide * 0.5,
				y + (height - font.height) * 0.5 + font.ascent, on ? theme.ink : theme.dim);
			pen += wide;
		}

		if (root.focus == this) {
			paint.outline(x, y, width, height, theme.accent, metrics.whole(1));
		}
	}
}
