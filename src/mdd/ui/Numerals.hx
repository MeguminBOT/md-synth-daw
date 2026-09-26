package mdd.ui;

@:unreflective

/**
	The decimal and hexadecimal spellings of small whole numbers, each made the first time it is
	asked for and kept, so a widget writing the same numbers every frame writes them without
	allocating. `Root` holds one for every widget under it.
**/
final class Numerals {
	/**
		The first number too large to keep. One from here up is spelt afresh every time.
	**/
	public static inline final KEPT = 1 << 16;

	final decimals:Array<String> = [];
	final hexes:Array<String> = [];

	/**
		Builds an empty set.
	**/
	public function new() {}

	/**
		@param value A whole number.
		@return It in decimal. One below nought or from `KEPT` up allocates every time.
	**/
	public function decimal(value:Int):String {
		if (value < 0 || value >= KEPT) return Std.string(value);

		while (decimals.length <= value) decimals.push(null);

		var said = decimals[value];

		if (said == null) {
			said = Std.string(value);
			decimals[value] = said;
		}

		return said;
	}

	/**
		@param value A whole number.
		@return It in upper case hexadecimal, at least two digits long. One below nought or from
			`KEPT` up allocates every time.
	**/
	public function hex(value:Int):String {
		if (value < 0 || value >= KEPT) return StringTools.hex(value, 2);

		while (hexes.length <= value) hexes.push(null);

		var said = hexes[value];

		if (said == null) {
			said = StringTools.hex(value, 2);
			hexes[value] = said;
		}

		return said;
	}
}
