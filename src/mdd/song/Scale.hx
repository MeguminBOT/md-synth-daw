package mdd.song;

import haxe.ds.Vector;

/**
	A key and a scale, for highlighting the rows of the piano roll.

	It changes nothing about what sounds. Rows outside the scale are drawn darker and
	the root row takes the channel colour, and that is the whole of it.
**/
@:unreflective
final class Scale {
	public static inline final CHROMATIC = 0;
	public static inline final MAJOR = 1;
	public static inline final MINOR = 2;
	static inline final HARMONIC = 3;
	static inline final DORIAN = 4;
	static inline final MIXOLYDIAN = 5;
	static inline final PENTATONIC = 6;
	static inline final MINOR_PENTATONIC = 7;
	static inline final BLUES = 8;

	/**
		How many scales there are.
	**/
	public static inline final KINDS = 9;

	/**
		Each scale as twelve bits, one per semitone above the root.
	**/
	static final SHAPES:Vector<Int> = Vector.fromArrayCopy([
		0xFFF,
		0xAB5,
		0x5AD,
		0x9AD,
		0x6AD,
		0x6B5,
		0x295,
		0x4A9,
		0x4E9
	]);

	/**
		The twelve root names, which are never translated.
	**/
	static final ROOTS:Array<String> = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A",
		"A#", "B"];

	/**
		Which root, 0 for C.
	**/
	public var root:Int = 0;

	/**
		Which scale, one of the nine.
	**/
	public var kind:Int = CHROMATIC;

	/**
		Builds a scale.

		@param root Which root, 0 for C.
		@param kind Which scale.
	**/
	public function new(root:Int = 0, kind:Int = CHROMATIC) {
		this.root = root;
		this.kind = kind;
	}

	/**
		@param pitch A MIDI note number.
		@return Whether it is in the scale.
	**/
	public inline function holds(pitch:Int):Bool {
		if (kind == CHROMATIC) return true;

		final within = ((pitch - root) % 12 + 12) % 12;
		return (SHAPES[kind] & (1 << within)) != 0;
	}

	/**
		@param pitch A MIDI note number.
		@return Whether it is the root, in any octave.
	**/
	public inline function rooted(pitch:Int):Bool {
		return ((pitch - root) % 12 + 12) % 12 == 0;
	}

	/**
		@return How many notes the scale has in an octave.
	**/
	public function degrees():Int {
		var many = 0;
		for (i in 0...12) if ((SHAPES[kind] & (1 << i)) != 0) many++;
		return many;
	}

	/**
		@param root A root, 0 for C.
		@return Its name.
	**/
	public static function rootOf(root:Int):String {
		return ROOTS[((root % 12) + 12) % 12];
	}

	/**
		@return A new scale with the same root and kind.
	**/
	public function copy():Scale {
		return new Scale(root, kind);
	}
}
