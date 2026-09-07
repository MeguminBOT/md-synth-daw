package mdd.ui;

import mdd.host.Text;

@:unreflective
final class Fallback {
	public var loaded(default, null):Bool = false;
	public var bytes(default, null):Float = 0;

	final paths:Array<String> = [];
	final faces:Array<Int> = [];

	public function new() {}

	public function adds(path:String):Void {
		if (paths.indexOf(path) >= 0) return;
		paths.push(path);
	}

	public function counted():Int {
		return paths.length;
	}

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
