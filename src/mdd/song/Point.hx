package mdd.song;

@:unreflective
final class Point {
	public var at:Int;
	public var value:Int;

	public var shape:Int = Automation.HOLD;
	public var tension:Int = 0;
	public var steps:Int = 0;

	public function new(at:Int, value:Int) {
		this.at = at;
		this.value = value;
	}

	public function copy():Point {
		final out = new Point(at, value);

		out.shape = shape;
		out.tension = tension;
		out.steps = steps;

		return out;
	}

	public inline function repeats():Int {
		return steps < 1 ? Automation.REPEATS : (steps > Automation.MOST_REPEATS
			? Automation.MOST_REPEATS : steps);
	}
}
