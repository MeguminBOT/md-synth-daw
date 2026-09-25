package mdd.song;

/**
	A time signature: how many beats a bar holds, and what note a beat is.

	It decides where bars fall and nothing else. The music plays the same whatever it says; the
	grid, the ruler, the bar count and the length a pattern grows by are what read it. A piece
	carries one, and a pattern may carry its own.
**/
@:unreflective
final class Meter {
	/**
		How many beats a bar holds, the upper number of the signature.
	**/
	public var beats(default, null):Int = 4;

	/**
		What note a beat is, the lower number: 4 for a quarter note, 8 for an eighth.
	**/
	public var unit(default, null):Int = 4;

	/**
		The most beats a bar may hold.
	**/
	public static inline final MOST_BEATS = 32;

	/**
		The upper numbers of the signatures offered to choose from, in order, beside `COMMON_UNITS`.
	**/
	public static final COMMON_BEATS:Array<Int> = [2, 3, 4, 5, 6, 7, 3, 5, 6, 7, 9, 12];

	/**
		The lower numbers of the signatures offered to choose from.
	**/
	public static final COMMON_UNITS:Array<Int> = [4, 4, 4, 4, 4, 4, 8, 8, 8, 8, 8, 8];

	/**
		@return Where it sits among the signatures offered, or -1 where it is none of them.
	**/
	public function common():Int {
		for (index in 0...COMMON_BEATS.length) {
			if (COMMON_BEATS[index] == beats && COMMON_UNITS[index] == unit) return index;
		}

		return -1;
	}

	/**
		Builds a signature, held to what one can be.

		@param beats How many beats a bar holds.
		@param unit What note a beat is.
	**/
	public function new(beats:Int = 4, unit:Int = 4) {
		sets(beats, unit);
	}

	/**
		Changes the signature, held to what one can be: one to `MOST_BEATS` beats, and a beat that
		is a whole note or a half, quarter, eighth, sixteenth or thirty second of one. A lower
		number that is none of those is read as a quarter.

		@param beats How many beats a bar holds.
		@param unit What note a beat is.
	**/
	public function sets(beats:Int, unit:Int):Void {
		this.beats = beats < 1 ? 1 : (beats > MOST_BEATS ? MOST_BEATS : beats);
		this.unit = switch (unit) {
			case 1, 2, 4, 8, 16, 32: unit;
			case _: 4;
		}
	}

	/**
		@param ppqn How many ticks a quarter note is.
		@return How many ticks a bar is, never less than one.
	**/
	public inline function bar(ppqn:Int):Int {
		final ticks = Math.round(ppqn * 4 * beats / unit);
		return ticks < 1 ? 1 : ticks;
	}

	/**
		@param ppqn How many ticks a quarter note is.
		@return How many ticks a beat is, never less than one.
	**/
	public inline function beat(ppqn:Int):Int {
		final ticks = Math.round(ppqn * 4 / unit);
		return ticks < 1 ? 1 : ticks;
	}

	/**
		@return A signature of its own with the same numbers.
	**/
	public function copy():Meter {
		return new Meter(beats, unit);
	}

	/**
		@param other Another signature.
		@return Whether the two say the same.
	**/
	public inline function same(other:Meter):Bool {
		return beats == other.beats && unit == other.unit;
	}

	/**
		@return It written the way a score writes it, as 3/4.
	**/
	public function spelt():String {
		return beats + "/" + unit;
	}
}
