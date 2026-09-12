package mdd.host;

@:include("draw.h")

/**
	Textures and the drawing calls that use them.

	Windows defaults to direct3d11. All six SDL backends open a window and paint a
	still interface correctly, and the fault in two of them appears only once the
	transport is running and the playhead, the scope and the meters are redrawing
	every frame. A flag or a setting names another, which is what makes the fault
	reachable to look at rather than only reportable.
**/
extern class Draw {
	/**
		Makes a texture to be updated from pixels, and answers with it.
	**/
	@:native("mdd_texture_create")
	public static function createTexture(renderer:cpp.Star<Canvas>, width:Int,
		height:Int):cpp.Star<Texture>;

	/**
		Makes a texture that can be drawn into.
	**/
	@:native("mdd_texture_target")
	public static function createTarget(renderer:cpp.Star<Canvas>, width:Int,
		height:Int):cpp.Star<Texture>;

	/**
		Replaces the whole of a texture from raw pixels. The height is the one the
		texture was made at, so only the width is given, and only to say how far apart
		two rows of pixels are.
	**/
	@:native("mdd_texture_update")
	public static function updateTexture(texture:cpp.Star<Texture>,
		rgba:cpp.RawConstPointer<cpp.UInt8>, width:Int):Void;

	/**
		Replaces one rectangle of it.
	**/
	@:native("mdd_texture_patch")
	public static function patchTexture(texture:cpp.Star<Texture>,
		rgba:cpp.RawConstPointer<cpp.UInt8>, x:Int, y:Int, width:Int, height:Int):Void;

	/**
		Destroys a texture.
	**/
	@:native("mdd_texture_destroy")
	public static function destroyTexture(texture:cpp.Star<Texture>):Void;

	/**
		Chooses whether a texture is smoothed when scaled.
	**/
	@:native("mdd_texture_scale_mode")
	static function textureSmooth(texture:cpp.Star<Texture>, smooth:Int):Void;

	/**
		Draws into a texture from here, or back into the window when given null.
	**/
	@:native("mdd_set_target")
	public static function setTarget(renderer:cpp.Star<Canvas>, texture:cpp.Star<Texture>):Void;

	/**
		Reads pixels back out of the target. A target cleared opaque has alpha 255
		everywhere, so a check looking for what was drawn has to test the colour channels.
	**/
	@:native("mdd_read_pixels")
	public static function readPixels(renderer:cpp.Star<Canvas>, x:Int, y:Int, width:Int,
		height:Int, rgba:cpp.RawPointer<cpp.UInt8>):Int;

	/**
		Draws triangles, with or without a texture. This is what every filled shape and
		every run of glyphs comes down to.
	**/
	@:native("mdd_render_geometry")
	public static function geometry(renderer:cpp.Star<Canvas>, texture:cpp.Star<Texture>,
		vertices:cpp.RawConstPointer<Single>, vertexCount:Int):Void;

	/**
		Draws one rectangle of a texture.
	**/
	@:native("mdd_render_texture")
	public static function texture(renderer:cpp.Star<Canvas>, texture:cpp.Star<Texture>, x:Single,
		y:Single, width:Single, height:Single, alpha:Single):Void;

	/**
		How many draw calls have been made since the last reset.
	**/
	@:native("mdd_draw_calls")
	public static function calls():Int;

	/**
		Sets that count back to nought.
	**/
	@:native("mdd_draw_calls_reset")
	public static function resetCalls():Void;
}
