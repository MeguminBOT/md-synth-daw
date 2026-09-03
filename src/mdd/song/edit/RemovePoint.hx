package mdd.song.edit;

final class RemovePoint implements Command {
	final pattern:Int;
	final part:Part;
	final target:Int;
	final slot:Int;
	final point:Point;
	final direct:Null<Automation>;

	public function new(pattern:Int, part:Part, target:Int, slot:Int, point:Point, direct:Null<Automation> = null) {
		this.pattern = pattern;
		this.part = part;
		this.target = target;
		this.slot = slot;
		this.point = point;
		this.direct = direct;
	}

	public function apply(song:Song):Void {
		final line = Points.line(song, pattern, part, target, slot, false, direct);
		if (line != null) line.remove(point);
	}

	public function revert(song:Song):Void {
		final line = Points.line(song, pattern, part, target, slot, true, direct);
		if (line != null) line.add(point);
	}

	public function label():String {
		return "remove a point";
	}
}
