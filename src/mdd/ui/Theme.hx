package mdd.ui;

import haxe.ds.Vector;

@:unreflective

/**
	Every colour the interface draws in, and the eleven a part is drawn in.

	A part keeps one colour everywhere it appears, which is what lets the rack, the
	playlist, the roll, the scope and the register timeline be read together.
**/
final class Theme {
	/**
		The colour of the first FM channel.
	**/
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

	/**
		One colour per part, in part order. Shared and never written to.
	**/
	public static final PARTS:Vector<Colour> = Vector.fromArrayCopy([
		FM1, FM2, FM3, FM4, FM5, FM6, PSG1, PSG2, PSG3, NOISE, DAC
	]);

	/**
		The dark theme.
	**/
	public static inline final MIDNIGHT = 0;
	static inline final RACK = 1;
	static inline final SLATE = 2;

	static final SURFACES:Vector<Colour> = Vector.fromArrayCopy([
		0x0C0C0C, 0x141414, 0x1E1E1E, 0x272727, 0x2F2F2F, 0x3A3A3A, 0x4A4A4A, 0x282828,
		0xEDEDED, 0xA0A0A0, 0x4C8FD8, 0xE8A85C, 0xE8615C,

		0x0A0906, 0x14120C, 0x201D16, 0x272319, 0x2E2920, 0x3A342A, 0x453E31, 0x241F18,
		0xE4DCC8, 0x968D79, 0xFF5A2E, 0xFFB25E, 0xFF4924,

		0x080B0F, 0x0E1216, 0x151A20, 0x1B222A, 0x222B34, 0x2C3742, 0x3A4753, 0x1A2027,
		0xE6EDF3, 0x8B98A5, 0x58AAE0, 0xE8A05A, 0xE5645A
	]);

	static inline final SPAN = 13;

	/**
		The colour behind everything.
	**/
	public var sink(default, null):Colour;

	/**
		The colour of the working area.
	**/
	public var ground(default, null):Colour;

	/**
		The colour of a panel.
	**/
	public var panel(default, null):Colour;

	/**
		One step above the panel.
	**/
	public var raise1(default, null):Colour;

	/**
		The colour of a title band.
	**/
	public var bar(default, null):Colour;

	/**
		Two steps above the panel.
	**/
	public var raise2(default, null):Colour;

	/**
		The colour of an outline.
	**/
	public var frame(default, null):Colour;

	/**
		The colour of a grid line.
	**/
	public var grid(default, null):Colour;

	/**
		The colour of ordinary text.
	**/
	public var ink(default, null):Colour;

	/**
		The colour of secondary text.
	**/
	public var dim(default, null):Colour;

	/**
		The colour of anything chosen or active.
	**/
	public var accent(default, null):Colour;

	/**
		The colour of a warning.
	**/
	public var warn(default, null):Colour;

	/**
		The colour drawn over a scrim.
	**/
	public var over(default, null):Colour;

	/**
		Which theme is worn.
	**/
	public var which(default, null):Colour;

	/**
		Builds a theme.

		@param which Which theme to wear.
	**/
	public function new(which:Int = MIDNIGHT) {
		wear(which);
	}

	/**
		Changes every colour to another theme.

		@param which Which theme to wear.
	**/
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

	/**
		@param index A part, 0 to 10.
		@return Its colour.
	**/
	public inline function part(index:Int):Colour {
		return index < 0 || index >= PARTS.length ? dim : PARTS[index];
	}

	/**
		How much a hovered thing is lifted.
	**/
	public static inline final HOVER = 0.10;

	/**
		How much a pressed thing is lifted.
	**/
	public static inline final PRESS = 0.18;

	/**
		How much a chosen thing is lifted.
	**/
	public static inline final SELECT = 0.24;

	/**
		@param colour A colour.
		@return It faded towards the ground, for something disabled.
	**/
	public inline function ghost(colour:Colour):Colour {
		return colour.mix(panel, 0.70);
	}

}
