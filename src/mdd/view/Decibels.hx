package mdd.view;

@:unreflective

/**
	How a level is written in decibels, the same way everywhere the interface shows one.
**/
final class Decibels {
	/**
		@param much How many decibels.
		@param places How many decimal places to keep.
		@return It rounded, with a plus sign where it is above nought, no sign where it rounds to
			nought, and the unit after it.
	**/
	public static function spelt(much:Float, places:Int):String {
		final scale = places <= 0 ? 1.0 : Math.pow(10, places);
		final held = Math.round(much * scale) / scale;

		return (held == 0 ? "0" : (held > 0 ? "+" : "") + held) + " dB";
	}
}
