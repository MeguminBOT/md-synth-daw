package mdd.song;

/**
	One point in an automation lane: a value at a tick, and the curve that reaches the
	next point.
**/
@:unreflective
final class Point {
	/**
		Where it sits, in ticks.
	**/
	public var at:Int;

	/**
		The value the lane holds there.
	**/
	public var value:Int;

	/**
		Which curve reaches the next point, from the shapes `Automation` names.
	**/
	public var shape:Int = Automation.HOLD;

	/**
		How hard that curve bends, 0 for not at all.
	**/
	public var tension:Int = 0;

	/**
		How many steps a stepped shape takes. Nought means the default.
	**/
	public var steps:Int = 0;

	/**
		Builds a point that holds its value until the next one.

		@param at Where it sits, in ticks.
		@param value The value it holds.
	**/
	public function new(at:Int, value:Int) {
		this.at = at;
		this.value = value;
	}

	/**
		@return A new point with the same values.
	**/
	public function copy():Point {
		final out = new Point(at, value);

		out.shape = shape;
		out.tension = tension;
		out.steps = steps;

		return out;
	}

	/**
		@return How many steps a stepped shape actually takes, held between one and the most
			allowed.
	**/
	public inline function repeats():Int {
		return steps < 1 ? Automation.REPEATS : (steps > Automation.MOST_REPEATS
			? Automation.MOST_REPEATS : steps);
	}
}
