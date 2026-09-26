package mdd.host;

@:include("text.h")

/**
	Glyph rasterising, through stb_truetype.

	A font is loaded once and asked for glyphs at a size. A variable font arrives at
	whatever weight its axis rests at, which is often not the regular, so the loader
	instances it to 400 as it reads it.
**/
extern class Text {
	/**
		Loads a font file and answers with a handle, or a negative number where it would
		not read.
	**/
	@:native("mdd_font_load")
	public static function load(path:cpp.ConstCharStar):Int;

	/**
		Gives a font back.
	**/
	@:native("mdd_font_free")
	public static function free(font:Int):Void;

	/**
		What weight the font was instanced to.
	**/
	@:native("mdd_font_weight")
	public static function weight(font:Int):Int;

	/**
		What weight its variation axis rested at before instancing, or nought where it has
		no axis.
	**/
	@:native("mdd_font_resting")
	public static function resting(font:Int):Int;

	/**
		How far above the baseline the face reaches, in pixels.
	**/
	@:native("mdd_font_ascent")
	public static function ascent(font:Int, pixels:Single):Single;

	/**
		How far below it, in pixels.
	**/
	@:native("mdd_font_descent")
	public static function descent(font:Int, pixels:Single):Single;

	/**
		How far apart two lines sit, in pixels.
	**/
	@:native("mdd_font_line")
	public static function line(font:Int, pixels:Single):Single;

	/**
		How large a glyph is, without drawing it. With oversampling the packed rectangle is
		larger than the glyph is drawn, and the width to use is the offset difference
		rather than the rectangle width.
	**/
	@:native("mdd_font_extent")
	public static function extent(font:Int, pixels:Single, codepoint:Int,
		wide:cpp.RawPointer<Int>, tall:cpp.RawPointer<Int>):Int;

	/**
		Draws one glyph into an atlas at a position.
	**/
	@:native("mdd_font_glyph")
	public static function glyph(font:Int, pixels:Single, codepoint:Int,
		rgba:cpp.RawPointer<cpp.UInt8>, atlasWidth:Int, atlasHeight:Int, atX:Int, atY:Int,
		glyph:cpp.RawPointer<Single>):Int;

	/**
		Draws a run of glyphs into an atlas in one pass.
	**/
	@:native("mdd_font_bake")
	public static function bake(font:Int, pixels:Single, first:Int, count:Int,
		rgba:cpp.RawPointer<cpp.UInt8>, atlasWidth:Int, atlasHeight:Int,
		glyphs:cpp.RawPointer<Single>):Int;
}
