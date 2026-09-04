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
		if (!select(which)) return;
		if (onChoose != null) onChoose(which);
	}

	public function select(which:Int):Bool {
		if (which < 0 || which >= labels.length || which == chosen) return false;

		chosen = which;
		invalidate();

		return true;
	}

	function widthOf(font:Font, metrics:Metrics, which:Int, squeeze:Float = 0):Float {
		return squeeze > 0 ? squeeze : font.measure(labels[which]) + metrics.inset * 2;
	}

	function squeezed(font:Font, metrics:Metrics):Float {
		if (labels.length == 0) return 0;

		var total = 0.0;
		for (i in 0...labels.length) total += widthOf(font, metrics, i);

		return total <= width ? 0 : width / labels.length;
	}

	public function at(px:Float):Int {
		final root = root();
		if (root == null || root.metrics.body == null) return -1;

		final font = root.metrics.body;
		final metrics = root.metrics;

		final squeeze = squeezed(font, metrics);

		var pen = x;
		for (i in 0...labels.length) {
			final wide = widthOf(font, metrics, i, squeeze);
			if (pen + wide > x + width + 0.5) return -1;
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

		paint.rect(x, y, width, height, theme.sink);
		paint.reface(font);

		final squeeze = squeezed(font, metrics);

		var pen = x;
		overflowed = 0;

		for (i in 0...labels.length) {
			final wide = widthOf(font, metrics, i, squeeze);

			if (pen + wide > x + width + 0.5) {
				overflowed = labels.length - i;
				paint.text("+" + overflowed, pen + metrics.unit, y + (height - font.height) * 0.5
					+ font.ascent, theme.dim);
				break;
			}

			final on = i == chosen;
			final gap = metrics.unit;
			final top = y + metrics.whole(3);
			final tall = height - metrics.whole(3);
			final left = pen + gap * 0.5;
			final room = wide - gap;
			final bar = metrics.whole(3);

			paint.roundedRect(left, top, room, tall + metrics.radiusRow, metrics.radiusRow,
				on ? theme.bar : theme.raise1);

			if (on) {
				paint.gradient(left, y + height - bar, room, bar,
					theme.accent.lift(0.20), theme.accent.sink(0.16));
			} else if (i == hoverAt) {
				paint.roundedRect(left, top, room, tall + metrics.radiusRow,
					metrics.radiusRow, theme.accent, Theme.HOVER);
			}

			if (squeeze > 0) paint.pushClip(pen, y, wide, height);

			paint.textCentred(labels[i], pen + wide * 0.5,
				y + (height + metrics.whole(3) - font.height) * 0.5 + font.ascent,
				on ? theme.ink : theme.dim);

			if (squeeze > 0) paint.popClip();
			pen += wide;
		}

		if (root.focus == this) {
			paint.outline(x, y, width, height, theme.accent, metrics.whole(1));
		}
	}
}
