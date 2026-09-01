package mdd.song;

@:unreflective
final class Clip {
	public var pattern:Int;
	public var at:Int;
	public var length:Int;
	public var transpose:Int;

	public function new(pattern:Int, at:Int, length:Int, transpose:Int = 0) {
		this.pattern = pattern;
		this.at = at;
		this.length = length;
		this.transpose = transpose;
	}

	public function copy():Clip {
		return new Clip(pattern, at, length, transpose);
	}

	public inline function ends():Int {
		return at + length;
	}
}
