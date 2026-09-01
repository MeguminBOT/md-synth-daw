package mdd.ui;

import haxe.ds.Vector;

@:unreflective
final class Theme {
	public static inline final FM1 = 0xFF5252;
	public static inline final FM2 = 0xFF9029;
	public static inline final FM3 = 0xFFD029;
	public static inline final FM4 = 0xB4E12E;
	public static inline final FM5 = 0x3FD98A;
	public static inline final FM6 = 0x2BC4B4;
	public static inline final PSG1 = 0x38A8F0;
	public static inline final PSG2 = 0x6C74F0;
	public static inline final PSG3 = 0xA65CF0;
	public static inline final NOISE = 0x9E9E9E;
	public static inline final DAC = 0xF050A0;

	public static final PARTS:Vector<Colour> = Vector.fromArrayCopy([
		FM1, FM2, FM3, FM4, FM5, FM6, PSG1, PSG2, PSG3, NOISE, DAC
	]);

	public static inline final MIDNIGHT = 0;
	public static inline final RACK = 1;
	public static inline final SLATE = 2;

	static final SURFACES:Vector<Colour> = Vector.fromArrayCopy([
		0x121212, 0x181818, 0x212121, 0x282828, 0x303030, 0x3A3A3A, 0x454545, 0x2A2A2A,
		0xE2E2E2, 0x909090, 0x3B6EA5, 0xE08A6A, 0xE05A5A,

		0x0C0B08, 0x17150F, 0x232019, 0x282419, 0x2C2820, 0x38332A, 0x3A342A, 0x1E1B15,
		0xD8D0BE, 0x8A8271, 0xFF4924, 0xFFA24A, 0xFF4924,

		0x0B0E12, 0x101418, 0x171D23, 0x1B222A, 0x1E262E, 0x253039, 0x2A343E, 0x1B222A,
		0xDDE4EA, 0x7F8C99, 0x4A9ECF, 0xE8A05A, 0xE5645A
	]);

	static inline final SPAN = 13;

	public var sink(default, null):Colour;
	public var ground(default, null):Colour;
	public var panel(default, null):Colour;
	public var raise1(default, null):Colour;
	public var bar(default, null):Colour;
	public var raise2(default, null):Colour;
	public var frame(default, null):Colour;
	public var grid(default, null):Colour;
	public var ink(default, null):Colour;
	public var dim(default, null):Colour;
	public var accent(default, null):Colour;
	public var warn(default, null):Colour;
	public var over(default, null):Colour;

	public var which(default, null):Colour;

	public function new(which:Int = MIDNIGHT) {
		wear(which);
	}

	public function wear(which:Int):Void {
		final at = (which < 0 || which > SLATE ? MIDNIGHT : which) * SPAN;
		this.which = which;

		sink = SURFACES[at];
		ground = SURFACES[at + 1];
		panel = SURFACES[at + 2];
		raise1 = SURFACES[at + 3];
		bar = SURFACES[at + 4];
		raise2 = SURFACES[at + 5];
		frame = SURFACES[at + 6];
		grid = SURFACES[at + 7];
		ink = SURFACES[at + 8];
		dim = SURFACES[at + 9];
		accent = SURFACES[at + 10];
		warn = SURFACES[at + 11];
		over = SURFACES[at + 12];
	}

	public inline function part(index:Int):Colour {
		return index < 0 || index >= PARTS.length ? dim : PARTS[index];
	}

	public static inline final HOVER = 0.10;
	public static inline final PRESS = 0.18;
	public static inline final SELECT = 0.24;

	public inline function ghost(colour:Colour):Colour {
		return colour.mix(panel, 0.70);
	}

}
