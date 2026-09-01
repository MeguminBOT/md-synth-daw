package mdd.ui.control;

@:unreflective
final class Meter extends Widget {
	public var level(default, null):Float = 0;
	public var peak(default, null):Float = 0;
	public var tint:Colour = 0x3B6EA5;
	public var vertical:Bool = true;
	public var segments:Int = 0;

	var held:Float = 0;

	public function new(tint:Colour) {
		super();
		this.tint = tint;
	}

	public function feed(next:Float, seconds:Float):Void {
		var value = next;
		if (value < 0) value = 0;
		if (value > 1) value = 1;

		level = value;

		if (value >= peak) {
			peak = value;
			held = 0.8;
		} else {
			held -= seconds;
			if (held <= 0) {
				peak -= seconds * 2.0;
				if (peak < value) peak = value;
			}
		}

		invalidate();
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null) return;

		final theme = root.theme;
		final metrics = root.metrics;

		paint.roundedRect(x, y, width, height, metrics.radiusSmall, theme.sink);

		if (segments > 0) {
			final gap = metrics.whole(1);
			final each = (height - gap * (segments - 1)) / segments;
			final lit = Math.round(level * segments);

			for (i in 0...segments) {
				if (i >= lit) continue;
				final top = y + height - (i + 1) * each - i * gap;
				final hot = i >= segments - 2;
				paint.rect(x, top, width, each, hot ? theme.over : tint);
			}
			return;
		}

		if (vertical) {
			final tall = height * level;
			paint.roundedRect(x, y + height - tall, width, tall, metrics.radiusSmall, tint);
			if (peak > 0) {
				paint.rect(x, y + height - height * peak, width, metrics.whole(2), theme.ink);
			}
		} else {
			paint.roundedRect(x, y, width * level, height, metrics.radiusSmall, tint);
			if (peak > 0) {
				paint.rect(x + width * peak, y, metrics.whole(2), height, theme.ink);
			}
		}
	}
}
