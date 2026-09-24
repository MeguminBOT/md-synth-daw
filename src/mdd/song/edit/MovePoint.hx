package mdd.song.edit;

/**
	Moves an automation point in time and value.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class MovePoint implements Command {
	final pattern:Int;
	final part:Part;
	final target:Int;
	final slot:Int;
	final point:Point;
	final direct:Null<Automation>;
	final at:Int;
	final value:Int;
	final preset:Int;

	var wasAt:Int = 0;
	var wasValue:Int = 0;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param pattern Which pattern, by index.
		@param part Which part of the pattern.
		@param target Which channel the lane belongs to, or -1 for the part's own.
		@param slot Which lane of that channel.
		@param point The point.
		@param at Which one, by index.
		@param value The new value for the point.
		@param direct The lane to act on, or null to look it up from the pattern.
		@param preset The instrument whose lane it is, by index, or -1 for the pattern's.
	**/
	public function new(pattern:Int, part:Part, target:Int, slot:Int, point:Point, at:Int,
			value:Int, direct:Null<Automation> = null, preset:Int = -1) {
		this.pattern = pattern;
		this.part = part;
		this.target = target;
		this.slot = slot;
		this.point = point;
		this.direct = direct;
		this.at = at;
		this.value = value;
		this.preset = preset;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		wasAt = point.at;
		wasValue = point.value;

		point.at = at;
		point.value = value;

		resort(song);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		point.at = wasAt;
		point.value = wasValue;

		resort(song);
	}

	function resort(song:Song):Void {
		final line = Points.line(song, pattern, part, target, slot, false, direct, preset);
		if (line != null) line.sort();
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "move a point";
	}
}
