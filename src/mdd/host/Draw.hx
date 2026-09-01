package mdd.host;

@:include("draw.h")
extern class Draw {
	@:native("mdd_texture_create")
	public static function createTexture(renderer:cpp.Star<Canvas>, width:Int,
		height:Int):cpp.Star<Texture>;

	@:native("mdd_texture_target")
	public static function createTarget(renderer:cpp.Star<Canvas>, width:Int,
		height:Int):cpp.Star<Texture>;

	@:native("mdd_texture_update")
	public static function updateTexture(texture:cpp.Star<Texture>,
		rgba:cpp.RawConstPointer<cpp.UInt8>, width:Int, height:Int):Void;

	@:native("mdd_texture_destroy")
	public static function destroyTexture(texture:cpp.Star<Texture>):Void;

	@:native("mdd_texture_scale_mode")
	public static function textureSmooth(texture:cpp.Star<Texture>, smooth:Int):Void;

	@:native("mdd_set_target")
	public static function setTarget(renderer:cpp.Star<Canvas>, texture:cpp.Star<Texture>):Void;

	@:native("mdd_read_pixels")
	public static function readPixels(renderer:cpp.Star<Canvas>, x:Int, y:Int, width:Int,
		height:Int, rgba:cpp.RawPointer<cpp.UInt8>):Int;

	@:native("mdd_render_geometry")
	public static function geometry(renderer:cpp.Star<Canvas>, texture:cpp.Star<Texture>,
		vertices:cpp.RawConstPointer<Single>, vertexCount:Int):Void;

	@:native("mdd_render_texture")
	public static function texture(renderer:cpp.Star<Canvas>, texture:cpp.Star<Texture>, x:Single,
		y:Single, width:Single, height:Single, alpha:Single):Void;

	@:native("mdd_draw_calls")
	public static function calls():Int;

	@:native("mdd_draw_calls_reset")
	public static function resetCalls():Void;
}
