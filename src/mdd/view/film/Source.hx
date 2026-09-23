package mdd.view.film;

import mdd.host.Texture;

/**
	A picture a style draws, as it was read from its file: the texture and the size it holds, or
	nothing where the file would not read. A `Picture` keeps one of these for every file it has
	been asked for.
**/
@:unreflective
final class Source {
	/**
		The file it was read from.
	**/
	public var path:String = "";

	/**
		The texture, or null where the file would not read.
	**/
	public var texture:cpp.Star<Texture> = null;

	/**
		How wide the picture is, in pixels.
	**/
	public var wide:Int = 0;

	/**
		How tall.
	**/
	public var tall:Int = 0;

	function new() {}

	/**
		@param path The file.
		@return A source for it with nothing read yet.
	**/
	public static function of(path:String):Source {
		final out = new Source();
		out.path = path;
		return out;
	}
}
