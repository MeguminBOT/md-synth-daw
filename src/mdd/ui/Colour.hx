package mdd.ui;

/**
	A packed colour, red in the high byte. It is an abstract over `Int`, so it costs
	nothing at run time and still cannot be mixed up with an ordinary number.
**/
abstract Colour(Int) from Int to Int {
	/**
		Builds a colour, dropping anything above the low three bytes.

		@param rgb The packed value.
	**/
	public inline function new(rgb:Int) {
		this = rgb & 0xFFFFFF;
	}

	/**
		The red channel, 0 to 255.
	**/
	public var red(get, never):Int;

	/**
		The green channel.
	**/
	public var green(get, never):Int;

	/**
		The blue channel.
	**/
	public var blue(get, never):Int;

	inline function get_red():Int return (this >> 16) & 0xFF;

	inline function get_green():Int return (this >> 8) & 0xFF;

	inline function get_blue():Int return this & 0xFF;

	/**
		@param into The colour to move towards.
		@param amount How far, 0 to 1.
		@return The blend of the two.
	**/
	public inline function mix(into:Colour, amount:Float):Colour {
		final keep = 1 - amount;
		return new Colour((Std.int(red * keep + into.red * amount) << 16)
			| (Std.int(green * keep + into.green * amount) << 8)
			| Std.int(blue * keep + into.blue * amount));
	}

	/**
		@param amount How far towards white, 0 to 1.
		@return A lighter colour.
	**/
	public inline function lift(amount:Float):Colour {
		return mix(0xFFFFFF, amount);
	}

	/**
		@param amount How far towards black, 0 to 1.
		@return A darker colour.
	**/
	public inline function sink(amount:Float):Colour {
		return mix(0x000000, amount);
	}

	/**
		@return The colour as a hexadecimal string, for a report.
	**/
	public function toString():String {
		return "#" + StringTools.hex(this, 6);
	}
}
