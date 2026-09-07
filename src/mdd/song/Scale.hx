package mdd.song;

import haxe.ds.Vector;

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
	public static inline final KINDS = 9;

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

	static final ROOTS:Array<String> = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A",
		"A#", "B"];

	public var root:Int = 0;
	public var kind:Int = CHROMATIC;

	public function new(root:Int = 0, kind:Int = CHROMATIC) {
		this.root = root;
		this.kind = kind;
	}

	public inline function holds(pitch:Int):Bool {
		if (kind == CHROMATIC) return true;

		final within = ((pitch - root) % 12 + 12) % 12;
		return (SHAPES[kind] & (1 << within)) != 0;
	}

	public inline function rooted(pitch:Int):Bool {
		return ((pitch - root) % 12 + 12) % 12 == 0;
	}

	public function degrees():Int {
		var many = 0;
		for (i in 0...12) if ((SHAPES[kind] & (1 << i)) != 0) many++;
		return many;
	}

	public static function rootOf(root:Int):String {
		return ROOTS[((root % 12) + 12) % 12];
	}

	public function copy():Scale {
		return new Scale(root, kind);
	}
}
