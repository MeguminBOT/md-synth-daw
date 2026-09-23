package mdd.host;

@:include("image.h")

/**
	Pictures read from files into textures: the backgrounds and the pictures a video draws.

	PNG and JPEG are read, and nothing wider or taller than `SIDE` pixels, so a picture cannot
	ask for more memory than a frame could use.
**/
extern class Image {
	/**
		The most pixels a picture may have on either side.
	**/
	@:native("MDD_IMAGE_SIDE")
	public static final SIDE:Int;

	/**
		Reads a picture into a texture at the size the file holds, alpha kept. The texture is the
		caller's to destroy.

		@param renderer The renderer the texture is for.
		@param path Where the file is.
		@param size Two ints the width and the height are written into, both nought where it
			fails.
		@return The texture, or null where the file will not open, is not a PNG or a JPEG, or is
			too large.
	**/
	@:native("mdd_image_load")
	public static function load(renderer:cpp.Star<Canvas>, path:cpp.ConstCharStar,
		size:cpp.RawPointer<Int>):cpp.Star<Texture>;
}
