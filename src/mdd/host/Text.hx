package mdd.host;

@:include("text.h")
extern class Text {
	@:native("mdd_font_load")
	public static function load(path:cpp.ConstCharStar):Int;

	@:native("mdd_font_free")
	public static function free(font:Int):Void;

	@:native("mdd_font_weight")
	public static function weight(font:Int):Int;

	@:native("mdd_font_resting")
	public static function resting(font:Int):Int;

	@:native("mdd_font_ascent")
	public static function ascent(font:Int, pixels:Single):Single;

	@:native("mdd_font_descent")
	public static function descent(font:Int, pixels:Single):Single;

	@:native("mdd_font_line")
	public static function line(font:Int, pixels:Single):Single;

	@:native("mdd_font_kern")
	static function kern(font:Int, pixels:Single, left:Int, right:Int):Single;

	@:native("mdd_font_extent")
	public static function extent(font:Int, pixels:Single, codepoint:Int,
		wide:cpp.RawPointer<Int>, tall:cpp.RawPointer<Int>):Int;

	@:native("mdd_font_glyph")
	public static function glyph(font:Int, pixels:Single, codepoint:Int,
		rgba:cpp.RawPointer<cpp.UInt8>, atlasWidth:Int, atlasHeight:Int, atX:Int, atY:Int,
		glyph:cpp.RawPointer<Single>):Int;

	@:native("mdd_font_bake")
	public static function bake(font:Int, pixels:Single, first:Int, count:Int,
		rgba:cpp.RawPointer<cpp.UInt8>, atlasWidth:Int, atlasHeight:Int,
		glyphs:cpp.RawPointer<Single>):Int;
}
