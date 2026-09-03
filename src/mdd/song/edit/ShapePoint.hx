package mdd.song.edit;

final class ShapePoint implements Command {
	final point:Point;
	final shape:Int;
	final tension:Int;
	final steps:Int;

	var wasShape:Int = 0;
	var wasTension:Int = 0;
	var wasSteps:Int = 0;

	public function new(point:Point, shape:Int, tension:Int, steps:Int) {
		this.point = point;
		this.shape = shape;
		this.tension = tension;
		this.steps = steps;
	}

	public function apply(song:Song):Void {
		wasShape = point.shape;
		wasTension = point.tension;
		wasSteps = point.steps;

		point.shape = shape;
		point.tension = tension;
		point.steps = steps;
	}

	public function revert(song:Song):Void {
		point.shape = wasShape;
		point.tension = wasTension;
		point.steps = wasSteps;
	}

	public function label():String {
		return "shape a point";
	}
}
