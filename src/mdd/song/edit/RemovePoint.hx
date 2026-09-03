package mdd.song.edit;

final class RemovePoint implements Command {
	final pattern:Int;
	final part:Part;
	final target:Int;
	final slot:Int;
	final point:Point;

	public function new(pattern:Int, part:Part, target:Int, slot:Int, point:Point) {
		this.pattern = pattern;
		this.part = part;
		this.target = target;
		this.slot = slot;
		this.point = point;
	}

	public function apply(song:Song):Void {
		final line = Points.line(song, pattern, part, target, slot, false);
		if (line != null) line.remove(point);
	}

	public function revert(song:Song):Void {
		final line = Points.line(song, pattern, part, target, slot, true);
		if (line != null) line.add(point);
	}

	public function label():String {
		return "remove a point";
	}
}
