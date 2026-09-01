package mdd.host;

@:include("text.h")
extern class Text {
	@:native("mdd_font_load")
	public static function load(path:cpp.ConstCharStar):Int;

	@:native("mdd_font_free")
	public static function free(font:Int):Void;

	@:native("mdd_font_ascent")
	public static function ascent(font:Int, pixels:Single):Single;

	@:native("mdd_font_descent")
	public static function descent(font:Int, pixels:Single):Single;

	@:native("mdd_font_line")
	public static function line(font:Int, pixels:Single):Single;

	@:native("mdd_font_kern")
	public static function kern(font:Int, pixels:Single, left:Int, right:Int):Single;

	@:native("mdd_font_bake")
	public static function bake(font:Int, pixels:Single, first:Int, count:Int,
		rgba:cpp.RawPointer<cpp.UInt8>, atlasWidth:Int, atlasHeight:Int,
		glyphs:cpp.RawPointer<Single>):Int;
}
