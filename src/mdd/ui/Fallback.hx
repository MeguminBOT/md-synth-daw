package mdd.ui;

import mdd.host.Text;

/**
	The faces a glyph is looked for in when the chosen one does not have it.

	They are loaded on the first miss rather than at start, because the CJK faces are
	most of what a package weighs and a session that never needs one should never pay
	for it.
**/
@:unreflective
final class Fallback {
	/**
		Whether the faces have been read yet.
	**/
	public var loaded(default, null):Bool = false;

	/**
		How much they weigh, in megabytes, for the status line.
	**/
	public var bytes(default, null):Float = 0;

	final paths:Array<String> = [];
	final faces:Array<Int> = [];

	/**
		Builds an empty fallback list.
	**/
	public function new() {}

	/**
		Adds a face to look in, unless it is already listed.

		@param path The font file.
	**/
	public function adds(path:String):Void {
		if (paths.indexOf(path) >= 0) return;
		paths.push(path);
	}

	/**
		@return How many faces are listed.
	**/
	public function counted():Int {
		return paths.length;
	}

	/**
		Reads the faces if they have not been read, and answers with them.

		@return The loaded faces, in the order they were added.
	**/
	public function held():Array<Int> {
		if (loaded) return faces;

		loaded = true;

		for (path in paths) {
			if (!sys.FileSystem.exists(path)) continue;

			final face = Text.load(path);
			if (face < 0) continue;

			faces.push(face);
			bytes += sys.FileSystem.stat(path).size;
		}

		return faces;
	}

	public function shut():Void {
		for (face in faces) Text.free(face);

		faces.resize(0);
		loaded = false;
		bytes = 0;
	}
}
