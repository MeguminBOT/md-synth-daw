package mdd.song.edit;

final class MovePoint implements Command {
	final pattern:Int;
	final part:Part;
	final target:Int;
	final slot:Int;
	final point:Point;
	final direct:Null<Automation>;
	final at:Int;
	final value:Int;

	var wasAt:Int = 0;
	var wasValue:Int = 0;

	public function new(pattern:Int, part:Part, target:Int, slot:Int, point:Point, at:Int,
			value:Int, direct:Null<Automation> = null) {
		this.pattern = pattern;
		this.part = part;
		this.target = target;
		this.slot = slot;
		this.point = point;
		this.direct = direct;
		this.at = at;
		this.value = value;
	}

	public function apply(song:Song):Void {
		wasAt = point.at;
		wasValue = point.value;

		point.at = at;
		point.value = value;

		resort(song);
	}

	public function revert(song:Song):Void {
		point.at = wasAt;
		point.value = wasValue;

		resort(song);
	}

	function resort(song:Song):Void {
		final line = Points.line(song, pattern, part, target, slot, false, direct);
		if (line != null) line.sort();
	}

	public function label():String {
		return "move a point";
	}
}
