package mdd.song.edit;

final class AddPoint implements Command {
	final pattern:Int;
	final part:Part;
	final target:Int;
	final slot:Int;
	final point:Point;
	final direct:Null<Automation>;

	var made:Bool = false;

	public function new(pattern:Int, part:Part, target:Int, slot:Int, point:Point, direct:Null<Automation> = null) {
		this.pattern = pattern;
		this.part = part;
		this.target = target;
		this.slot = slot;
		this.point = point;
		this.direct = direct;
	}

	public function apply(song:Song):Void {
		final line = Points.line(song, pattern, part, target, slot, true, direct);
		if (line == null) return;

		made = line.points.length == 0;
		line.add(point);
	}

	public function revert(song:Song):Void {
		final line = Points.line(song, pattern, part, target, slot, false, direct);
		if (line == null) return;

		line.remove(point);
		if (made) Points.drop(song, pattern, part, line, direct);
	}

	public function label():String {
		return "add a point";
	}
}
