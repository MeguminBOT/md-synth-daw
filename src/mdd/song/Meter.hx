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
		Every lower number a signature may have, in order: a whole note down to a thirty second.
	**/
	public static final UNITS:Array<Int> = [1, 2, 4, 8, 16, 32];

	/**
		The upper numbers of the signatures a pattern's menu offers in one click, in order, beside
		`COMMON_UNITS`. Any other is typed.
	**/
	public static final COMMON_BEATS:Array<Int> = [2, 3, 4, 5, 6, 7, 3, 5, 6, 7, 9, 12];

	/**
		The lower numbers of those signatures.
	**/
	public static final COMMON_UNITS:Array<Int> = [4, 4, 4, 4, 4, 4, 8, 8, 8, 8, 8, 8];

	/**
		Reads a signature written the way a score writes it.

		@param said The signature, as 7/8, with or without spaces around the stroke.
		@return It, or null where it is not one a signature can be: an upper number from one to
			`MOST_BEATS` and a lower one from `UNITS`. Nothing is held to a limit here, so a typed
			33/8 is refused rather than read as 32/8.
	**/
	public static function read(said:String):Null<Meter> {
		final written = ~/^\s*(\d{1,3})\s*\/\s*(\d{1,3})\s*$/;
		if (!written.match(said)) return null;

		final beats:Int = Std.parseInt(written.matched(1));
		final unit:Int = Std.parseInt(written.matched(2));

		if (beats < 1 || beats > MOST_BEATS || UNITS.indexOf(unit) < 0) return null;
		return new Meter(beats, unit);
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
		is one of `UNITS`. A lower number that is none of those is read as a quarter.

		@param beats How many beats a bar holds.
		@param unit What note a beat is.
	**/
	public function sets(beats:Int, unit:Int):Void {
		this.beats = beats < 1 ? 1 : (beats > MOST_BEATS ? MOST_BEATS : beats);
		this.unit = UNITS.indexOf(unit) >= 0 ? unit : 4;
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
