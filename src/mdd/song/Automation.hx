package mdd.song;

@:unreflective
final class Automation {
	public var target:Int;
	public var slot:Int;
	public final points:Array<Point> = [];

	public function new(target:Int, slot:Int = 0) {
		this.target = target;
		this.slot = slot;
	}

	public function add(point:Point):Point {
		var at = points.length;
		while (at > 0 && points[at - 1].at > point.at) at--;

		points.insert(at, point);
		return point;
	}

	public function valueAt(tick:Int):Int {
		if (points.length == 0) return -1;
		if (tick <= points[0].at) return points[0].value;

		var last = points[0];

		for (i in 1...points.length) {
			final point = points[i];
			if (point.at > tick) {
				final span = point.at - last.at;
				if (span <= 0) return point.value;

				final part = (tick - last.at) / span;
				return last.value + Std.int((point.value - last.value) * part);
			}
			last = point;
		}

		return last.value;
	}
}
