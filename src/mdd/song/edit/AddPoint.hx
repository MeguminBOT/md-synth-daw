package mdd.song.edit;

final class AddPoint implements Command {
	final pattern:Int;
	final part:Part;
	final target:Int;
	final slot:Int;
	final point:Point;

	var made:Bool = false;

	public function new(pattern:Int, part:Part, target:Int, slot:Int, point:Point) {
		this.pattern = pattern;
		this.part = part;
		this.target = target;
		this.slot = slot;
		this.point = point;
	}

	public function apply(song:Song):Void {
		final line = Points.line(song, pattern, part, target, slot, true);
		if (line == null) return;

		made = line.points.length == 0;
		line.add(point);
	}

	public function revert(song:Song):Void {
		final line = Points.line(song, pattern, part, target, slot, false);
		if (line == null) return;

		line.remove(point);
		if (made) Points.drop(song, pattern, part, line);
	}

	public function label():String {
		return "add a point";
	}
}
