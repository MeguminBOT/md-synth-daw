package mdd.ui;

import haxe.ds.Vector;

@:unreflective

/**
	Every colour the interface draws in, and the eleven a part is drawn in.

	A part keeps one colour everywhere it appears, which is what lets the rack, the
	playlist, the roll, the scope and the register timeline be read together. The part colours
	drawn follow the theme, so a light theme draws them deep enough to read on its ground, and a
	set told apart with the common forms of colour blindness can take their place in either.
**/
final class Theme {
	/**
		The colour of the first FM channel in the standard set on a dark theme. These eleven are
		also what a colour chosen for a track or a pattern is stored as, whatever is worn.
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
		One colour per part, in part order, in the standard set on a dark theme. Shared and never
		written to.
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

	/**
		Material's dark scheme.
	**/
	public static inline final MATERIAL = 3;

	/**
		Fluent's dark scheme.
	**/
	public static inline final FLUENT = 4;

	/**
		Material's light scheme.
	**/
	public static inline final MATERIAL_LIGHT = 5;

	/**
		Fluent's light scheme.
	**/
	public static inline final FLUENT_LIGHT = 6;

	/**
		A soft light theme.
	**/
	public static inline final PASTEL = 7;

	/**
		How many themes there are.
	**/
	public static inline final COUNT = 8;

	/**
		Part colours: the standard set.
	**/
	public static inline final STANDARD = 0;

	/**
		Part colours: a set told apart with the common forms of colour blindness, the warm colours
		for the FM parts and the cool ones for the square parts.
	**/
	public static inline final SAFE = 1;

	static final SURFACES:Vector<Colour> = Vector.fromArrayCopy([
		0x0C0C0C, 0x141414, 0x1E1E1E, 0x272727, 0x2F2F2F, 0x3A3A3A, 0x4A4A4A, 0x282828,
		0xEDEDED, 0xA0A0A0, 0x4C8FD8, 0xE8A85C, 0xE8615C, 0x0C0C0C, 0xEDEDED, 0x0C0C0C,

		0x0A0906, 0x14120C, 0x201D16, 0x272319, 0x2E2920, 0x3A342A, 0x453E31, 0x241F18,
		0xE4DCC8, 0x968D79, 0xFF5A2E, 0xFFB25E, 0xFF4924, 0x0A0906, 0xE4DCC8, 0x0A0906,

		0x080B0F, 0x0E1216, 0x151A20, 0x1B222A, 0x222B34, 0x2C3742, 0x3A4753, 0x1A2027,
		0xE6EDF3, 0x8B98A5, 0x58AAE0, 0xE8A05A, 0xE5645A, 0x080B0F, 0xE6EDF3, 0x080B0F,

		0x0F0D13, 0x141218, 0x1D1B20, 0x211F26, 0x2B2930, 0x36343B, 0x49454F, 0x2B2930,
		0xE6E0E9, 0xCAC4D0, 0xD0BCFF, 0xFFB870, 0xF2B8B5, 0x0F0D13, 0xE6E0E9, 0x0F0D13,

		0x141414, 0x1C1C1C, 0x202020, 0x2B2B2B, 0x2D2D2D, 0x3A3A3A, 0x454545, 0x2A2A2A,
		0xFFFFFF, 0xC5C5C5, 0x60CDFF, 0xFCE100, 0xFF99A4, 0x0A0A0A, 0xF0F0F0, 0x141414,

		0xE6E0E9, 0xFEF7FF, 0xF7F2FA, 0xF3EDF7, 0xECE6F0, 0xE6E0E9, 0xCAC4D0, 0xE7E0EC,
		0x1D1B20, 0x49454F, 0x9A82DB, 0xB26A00, 0xB3261E, 0x1D1B20, 0xFFFFFF, 0x1D1B20,

		0xE5E5E5, 0xF9F9F9, 0xF3F3F3, 0xFBFBFB, 0xEBEBEB, 0xE0E0E0, 0xCFCFCF, 0xE6E6E6,
		0x1A1A1A, 0x5D5D5D, 0x4CA0E0, 0xA86200, 0xC42B1C, 0x1A1A1A, 0xFFFFFF, 0x1A1A1A,

		0xEDE6F2, 0xFBF8F3, 0xF5F0EA, 0xFFFDF9, 0xEFE8F3, 0xE8E0EC, 0xD9CFE0, 0xEEE7EF,
		0x3A3440, 0x7C7385, 0xE59BB6, 0xC07A2A, 0xC4495A, 0x3A3440, 0xFFFDF9, 0x4A4452
	]);

	static inline final SPAN = 16;

	static final LIGHT:Vector<Bool> = Vector.fromArrayCopy([false, false, false, false, false, true,
		true, true]);

	static final LIGHT_PARTS:Vector<Colour> = Vector.fromArrayCopy([
		0xD32F2F, 0xE06C00, 0xB38F00, 0x6E9C00, 0x14A06A, 0x00897B, 0x1E7FC8, 0x4B55D1, 0x8A3FD1,
		0x6E6E6E, 0xC2185B
	]);

	static final SAFE_PARTS:Vector<Colour> = Vector.fromArrayCopy([
		0xE69F00, 0xD55E00, 0xF0E442, 0xCC79A7, 0xFFD18A, 0xF2B6D4, 0x56B4E9, 0x3D8FE0, 0x2EC4A0,
		0xB0B0B0, 0xFFFFFF
	]);

	static final SAFE_LIGHT_PARTS:Vector<Colour> = Vector.fromArrayCopy([
		0xB87A00, 0xB24C00, 0x8C8500, 0xA8538A, 0xD68A1E, 0xC0689A, 0x2A86C0, 0x0060A0, 0x007A58,
		0x6E6E6E, 0x202020
	]);

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
		The colour a shadow or a scrim is drawn in over whatever is under it, which stays dark on
		a light theme. Shading inside a view is drawn in `sink` instead.
	**/
	public var shade(default, null):Colour;

	/**
		The colour of a white key.
	**/
	public var ivory(default, null):Colour;

	/**
		The colour of a black key.
	**/
	public var ebony(default, null):Colour;

	/**
		Which theme is worn.
	**/
	public var which(default, null):Colour;

	/**
		Whether the theme worn is a light one.
	**/
	public var light(default, null):Bool = false;

	/**
		Which set of part colours is worn, `STANDARD` or `SAFE`.
	**/
	public var palette(default, null):Int = STANDARD;

	var parts:Vector<Colour> = PARTS;

	/**
		Builds a theme.

		@param which Which theme to wear.
	**/
	public function new(which:Int = MIDNIGHT) {
		wear(which);
	}

	/**
		Changes every colour to another theme, keeping the set of part colours worn.

		@param which Which theme to wear.
	**/
	public function wear(which:Int):Void {
		final picked = which < 0 || which >= COUNT ? MIDNIGHT : which;
		final at = picked * SPAN;

		this.which = picked;
		light = LIGHT[picked];

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
		shade = SURFACES[at + 13];
		ivory = SURFACES[at + 14];
		ebony = SURFACES[at + 15];

		parted();
	}

	/**
		Changes the part colours to another set, for the theme worn now.

		@param palette `STANDARD` or `SAFE`.
	**/
	public function chooses(palette:Int):Void {
		this.palette = palette == SAFE ? SAFE : STANDARD;
		parted();
	}

	function parted():Void {
		parts = palette == SAFE ? (light ? SAFE_LIGHT_PARTS : SAFE_PARTS)
			: (light ? LIGHT_PARTS : PARTS);
	}

	/**
		@param index A part, 0 to 10.
		@return Its colour, in the set and for the theme worn.
	**/
	public inline function part(index:Int):Colour {
		return index < 0 || index >= parts.length ? dim : parts[index];
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
