package mdd.ui;

abstract Colour(Int) from Int to Int {
	public inline function new(rgb:Int) {
		this = rgb & 0xFFFFFF;
	}

	public var red(get, never):Int;
	public var green(get, never):Int;
	public var blue(get, never):Int;

	inline function get_red():Int return (this >> 16) & 0xFF;

	inline function get_green():Int return (this >> 8) & 0xFF;

	inline function get_blue():Int return this & 0xFF;

	public inline function mix(into:Colour, amount:Float):Colour {
		final keep = 1 - amount;
		return new Colour((Std.int(red * keep + into.red * amount) << 16)
			| (Std.int(green * keep + into.green * amount) << 8)
			| Std.int(blue * keep + into.blue * amount));
	}

	public inline function lift(amount:Float):Colour {
		return mix(0xFFFFFF, amount);
	}

	public inline function sink(amount:Float):Colour {
		return mix(0x000000, amount);
	}

	public function toString():String {
		return "#" + StringTools.hex(this, 6);
	}
}
