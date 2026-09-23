package mdd.ui.control;

@:unreflective

/**
	A colour picker, raised as a sheet: a square of saturation across and brightness down for the
	hue chosen on the strip beside it, and the colour as `#RRGGBB` in a field under them.

	The colour changes as it is dragged, so what is being coloured follows it, and `onChange` is
	called with each step. A click outside it or Escape closes it where it is, and Return in the
	field takes what was typed.
**/
final class Picker extends Widget {
	static inline final NONE = 0;
	static inline final SQUARE = 1;
	static inline final STRIP = 2;

	/**
		How many cells the square is drawn in across and down, which is what keeps its blend
		even.
	**/
	static inline final CELLS = 12;

	/**
		The colour chosen, as `0xRRGGBB`.
	**/
	public var colour(default, null):Int = 0xFFFFFF;

	/**
		What the picker is choosing, shown over it.
	**/
	public var title:String = "";

	/**
		Called with the colour each time it changes.
	**/
	public var onChange:Null<Int -> Void> = null;

	/**
		Called when it closes.
	**/
	public var onShut:Null<Void -> Void> = null;

	final hex:Field;

	var hue:Float = 0;
	var saturation:Float = 0;
	var brightness:Float = 1;
	var dragging:Int = NONE;

	/**
		Builds a picker holding white.
	**/
	public function new() {
		super();

		modal = true;
		focusable = true;
		opaque = true;

		hex = new Field("");
		add(hex);

		hex.onCommit = function(said:String):Void {
			final held = parsed(said);
			if (held >= 0) takes(held, true);
		};
	}

	/**
		Sets the colour it opens on, without calling `onChange`.

		@param colour The colour, as `0xRRGGBB`.
	**/
	public function beginsAt(colour:Int):Void {
		takes(colour & 0xFFFFFF, false);
	}

	override function lowered():Void {
		dragging = NONE;
		if (onShut != null) onShut();
	}

	function side():Float {
		final root = root();
		return root == null ? 200 : root.metrics.whole(200);
	}

	function strip():Float {
		final root = root();
		return root == null ? 22 : root.metrics.whole(22);
	}

	function pad():Float {
		final root = root();
		return root == null ? 14 : root.metrics.whole(14);
	}

	function top():Float {
		final root = root();
		return y + pad() + (root == null ? 18 : root.metrics.whole(22));
	}

	override function measure(availableWidth:Float, availableHeight:Float):Void {
		final root = root();
		final control = root == null ? 28 : root.metrics.control;

		wantWidth = pad() * 3 + side() + strip();
		wantHeight = top() - y + side() + pad() * 2 + control;
	}

	override function layout():Void {
		final root = root();
		final control = root == null ? 28 : root.metrics.control;

		hex.arrange(x + pad(), top() + side() + pad(), side() + pad() + strip(), control);
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				if (event.button != Pointer.Left) return true;

				if (!accepts(event.x, event.y)) {
					shuts();
					return true;
				}

				dragging = inSquare(event.x, event.y) ? SQUARE : (inStrip(event.x, event.y) ? STRIP : NONE);
				dragged(event.x, event.y);

				return true;

			case Kind.PointerMove:
				if (dragging == NONE) return false;

				dragged(event.x, event.y);
				return true;

			case Kind.PointerUp:
				dragging = NONE;
				return true;

			case _:
		}

		return false;
	}

	function shuts():Void {
		final root = root();
		if (root != null && root.sheet == this) root.lower();
	}

	function inSquare(px:Float, py:Float):Bool {
		final left = x + pad();
		return px >= left && px < left + side() && py >= top() && py < top() + side();
	}

	function inStrip(px:Float, py:Float):Bool {
		final left = x + pad() * 2 + side();
		return px >= left && px < left + strip() && py >= top() && py < top() + side();
	}

	function dragged(px:Float, py:Float):Void {
		final along = clamped((px - x - pad()) / side());
		final down = clamped((py - top()) / side());

		switch (dragging) {
			case SQUARE:
				saturation = along;
				brightness = 1 - down;

			case STRIP:
				hue = down * 360;

			case _:
				return;
		}

		colour = rgbOf(hue, saturation, brightness);
		hex.set(spelt(colour));

		if (onChange != null) onChange(colour);
		invalidate();
	}

	function takes(held:Int, tells:Bool):Void {
		colour = held;

		final red = ((held >> 16) & 0xFF) / 255;
		final green = ((held >> 8) & 0xFF) / 255;
		final blue = (held & 0xFF) / 255;
		final most = red > green ? (red > blue ? red : blue) : (green > blue ? green : blue);
		final least = red < green ? (red < blue ? red : blue) : (green < blue ? green : blue);
		final span = most - least;

		brightness = most;
		saturation = most <= 0 ? 0 : span / most;

		if (span > 0) {
			var turned = most == red ? (green - blue) / span : (most == green ? 2 + (blue - red) / span
				: 4 + (red - green) / span);

			turned *= 60;
			hue = turned < 0 ? turned + 360 : turned;
		}

		hex.set(spelt(held));

		if (tells && onChange != null) onChange(held);
		invalidate();
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final font = metrics.small == null ? metrics.body : metrics.small;
		final side = side();
		final left = x + pad();
		final upper = top();
		final cell = side / CELLS;

		paint.roundedRect(x, y, width, height, metrics.radiusPanel, theme.raise1);
		paint.outline(x, y, width, height, theme.frame, metrics.whole(1), 1, metrics.radiusPanel);

		paint.reface(font);
		paint.text(title, left, y + pad() + font.ascent, theme.dim, 0.9);

		for (row in 0...CELLS) {
			for (column in 0...CELLS) {
				final paler = column / CELLS;
				final richer = (column + 1) / CELLS;
				final brighter = 1 - row / CELLS;
				final darker = 1 - (row + 1) / CELLS;

				paint.tinted(left + column * cell, upper + row * cell, cell + 0.5, cell + 0.5,
					rgbOf(hue, paler, brighter), rgbOf(hue, richer, brighter), rgbOf(hue, richer, darker),
					rgbOf(hue, paler, darker));
			}
		}

		final stripLeft = left + side + pad();
		final band = side / 6;

		for (step in 0...6) {
			paint.gradient(stripLeft, upper + step * band, strip(), band + 0.5,
				rgbOf(step * 60, 1, 1), rgbOf((step + 1) * 60, 1, 1));
		}

		final dot = metrics.whole(5);
		final markX = left + saturation * side;
		final markY = upper + (1 - brightness) * side;

		paint.arc(markX, markY, dot, 0, Math.PI * 2, metrics.whole(2), brightness > 0.6 ? 0x000000
			: 0xFFFFFF);

		final hueAt = upper + hue / 360 * side;
		paint.rect(stripLeft - metrics.whole(2), hueAt - metrics.whole(1), strip() + metrics.whole(4),
			metrics.whole(2), theme.ink);

		paint.outline(left, upper, side, side, theme.frame, metrics.whole(1), 1, 0);
	}

	static inline function clamped(value:Float):Float {
		return value < 0 ? 0 : (value > 1 ? 1 : value);
	}

	/**
		@param hue The hue, 0 to 360.
		@param saturation The saturation, 0 to 1.
		@param brightness The brightness, 0 to 1.
		@return The colour, as `0xRRGGBB`.
	**/
	public static function rgbOf(hue:Float, saturation:Float, brightness:Float):Int {
		final turned = (hue % 360 + 360) % 360 / 60;
		final sector = Std.int(turned);
		final part = turned - sector;

		final floor = brightness * (1 - saturation);
		final falling = brightness * (1 - saturation * part);
		final rising = brightness * (1 - saturation * (1 - part));

		final red = switch (sector) {
			case 0, 5: brightness;
			case 1: falling;
			case 2, 3: floor;
			case _: rising;
		};

		final green = switch (sector) {
			case 0: rising;
			case 1, 2: brightness;
			case 3: falling;
			case _: floor;
		};

		final blue = switch (sector) {
			case 0, 1: floor;
			case 2: rising;
			case 3, 4: brightness;
			case _: falling;
		};

		return (channel(red) << 16) | (channel(green) << 8) | channel(blue);
	}

	static inline function channel(value:Float):Int {
		final held = Math.round(value * 255);
		return held < 0 ? 0 : (held > 255 ? 255 : held);
	}

	/**
		@param colour A colour, as `0xRRGGBB`.
		@return It as `#RRGGBB`.
	**/
	public static function spelt(colour:Int):String {
		return "#" + StringTools.hex(colour & 0xFFFFFF, 6);
	}

	/**
		@param said What was typed: six hexadecimal digits, with or without a `#` in front.
		@return The colour, or -1 where it is not one.
	**/
	public static function parsed(said:String):Int {
		final held = StringTools.trim(said);
		final digits = StringTools.startsWith(held, "#") ? held.substr(1) : held;

		if (digits.length != 6) return -1;

		for (index in 0...6) {
			final code = digits.charCodeAt(index);
			if (code == null) return -1;

			final hexadecimal = (code >= "0".code && code <= "9".code) || (code >= "a".code
				&& code <= "f".code) || (code >= "A".code && code <= "F".code);

			if (!hexadecimal) return -1;
		}

		final value = Std.parseInt("0x" + digits);
		return value == null ? -1 : value;
	}
}
