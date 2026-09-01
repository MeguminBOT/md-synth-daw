package mdd.song;

@:unreflective
final class Point {
	public var at:Int;
	public var value:Int;

	public function new(at:Int, value:Int) {
		this.at = at;
		this.value = value;
	}

	public function copy():Point {
		return new Point(at, value);
	}
}
