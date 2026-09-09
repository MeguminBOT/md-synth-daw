package mdd.song.edit;

/**
	Changes the curve that reaches the next automation point.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class ShapePoint implements Command {
	final point:Point;
	final shape:Int;
	final tension:Int;
	final steps:Int;

	var wasShape:Int = 0;
	var wasTension:Int = 0;
	var wasSteps:Int = 0;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param point The point.
		@param shape Which curve reaches the next point.
		@param tension How hard that curve bends.
		@param steps How many steps a stepped shape takes.
	**/
	public function new(point:Point, shape:Int, tension:Int, steps:Int) {
		this.point = point;
		this.shape = shape;
		this.tension = tension;
		this.steps = steps;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		wasShape = point.shape;
		wasTension = point.tension;
		wasSteps = point.steps;

		point.shape = shape;
		point.tension = tension;
		point.steps = steps;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		point.shape = wasShape;
		point.tension = wasTension;
		point.steps = wasSteps;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "shape a point";
	}
}
