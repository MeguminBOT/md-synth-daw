package mdd.song.edit;

/**
	Puts a point in an automation lane.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class AddPoint implements Command {
	final pattern:Int;
	final part:Part;
	final target:Int;
	final slot:Int;
	final point:Point;
	final direct:Null<Automation>;

	var made:Bool = false;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param pattern Which pattern, by index.
		@param part Which part of the pattern.
		@param target Which channel the lane belongs to, or -1 for the part's own.
		@param slot Which lane of that channel.
		@param point The point.
		@param direct The lane to act on, or null to look it up from the pattern.
	**/
	public function new(pattern:Int, part:Part, target:Int, slot:Int, point:Point, direct:Null<Automation> = null) {
		this.pattern = pattern;
		this.part = part;
		this.target = target;
		this.slot = slot;
		this.point = point;
		this.direct = direct;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		final line = Points.line(song, pattern, part, target, slot, true, direct);
		if (line == null) return;

		made = line.points.length == 0;
		line.add(point);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		final line = Points.line(song, pattern, part, target, slot, false, direct);
		if (line == null) return;

		line.remove(point);
		if (made) Points.drop(song, pattern, part, line, direct);
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "add a point";
	}
}
