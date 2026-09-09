package mdd.ui.control;

@:unreflective

/**
	A level meter, with a peak that falls back slowly so a transient can be seen.
**/
final class Meter extends Widget {
	/**
		The level now, 0 to 1.
	**/
	public var level(default, null):Float = 0;

	/**
		The highest recently, falling back.
	**/
	public var peak(default, null):Float = 0;

	/**
		What colour to draw it.
	**/
	public var tint:Colour = 0x3B6EA5;

	/**
		Whether it fills upwards rather than across.
	**/
	public var vertical:Bool = true;

	/**
		How many blocks to draw it in, or nought for a continuous bar.
	**/
	public var segments:Int = 0;

	var held:Float = 0;

	/**
		Builds an empty meter.

		@param tint What colour to draw it.
	**/
	public function new(tint:Colour) {
		super();
		this.tint = tint;
	}

	/**
		Gives it a new level and lets the peak fall.

		@param next The level now, 0 to 1.
		@param seconds How long since the last call.
	**/
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
