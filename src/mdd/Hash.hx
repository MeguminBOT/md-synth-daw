package mdd;

import haxe.Int64;

/**
	A sixty four bit hash and the pieces that feed it, for working out what a thing is from
	everything it holds rather than from what it is called.

	It is FNV-1a with an avalanche on the end, taken twice from two seeds where a wider answer is
	wanted. That is enough to tell one preset from another: two presets differing anywhere come
	out apart, and nothing here is meant to stand against someone setting out to make two things
	collide on purpose.
**/
class Hash {
	static final PRIME:Int64 = Int64.make(0x00000100, 0x000001B3);

	/**
		@param high The top half of the seed.
		@param low The bottom half.
		@return A hash to feed.
	**/
	public static inline function seeded(high:Int, low:Int):Int64 {
		return Int64.make(high, low);
	}

	/**
		@param held What has been fed so far.
		@param value A whole number to feed it, every byte of it.
		@return The hash with that number in it.
	**/
	public static function whole(held:Int64, value:Int):Int64 {
		var out = held;

		out = (out ^ Int64.ofInt(value & 0xFF)) * PRIME;
		out = (out ^ Int64.ofInt((value >> 8) & 0xFF)) * PRIME;
		out = (out ^ Int64.ofInt((value >> 16) & 0xFF)) * PRIME;
		out = (out ^ Int64.ofInt((value >>> 24) & 0xFF)) * PRIME;

		return out;
	}

	/**
		@param held What has been fed so far.
		@param value Text to feed it, its length first, so that two fields running together cannot
			read as the same thing split another way.
		@return The hash with that text in it.
	**/
	public static function said(held:Int64, value:String):Int64 {
		var out = whole(held, value.length);

		for (at in 0...value.length) out = whole(out, value.charCodeAt(at));

		return out;
	}

	/**
		@param held A fed hash.
		@return It mixed, so that every bit of what went in reaches every bit of what comes out.
	**/
	public static function settled(held:Int64):Int64 {
		var out = held;

		out = (out ^ (out >>> 33)) * Int64.make(0xFF51AFD7, 0xED558CCD);
		out = (out ^ (out >>> 33)) * Int64.make(0xC4CEB9FE, 0x1A85EC53);

		return out ^ (out >>> 33);
	}

	/**
		@param held A hash.
		@return It as sixteen hexadecimal characters.
	**/
	public static function spelt(held:Int64):String {
		return StringTools.hex(held.high, 8).toLowerCase()
			+ StringTools.hex(held.low, 8).toLowerCase();
	}
}
