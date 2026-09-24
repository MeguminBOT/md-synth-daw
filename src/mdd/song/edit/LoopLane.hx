package mdd.song.edit;

/**
	Makes a lane a preset carries go back to one of its points each time it passes its last, or
	hold its last value instead.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class LoopLane implements Command {
	final preset:Int;
	final target:Int;
	final slot:Int;
	final loop:Int;

	var was:Int = -1;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param preset Which instrument, by index.
		@param target Which parameter the lane moves.
		@param slot Which operator, for a per operator one.
		@param loop Which point to go back to, by index, or -1 to hold the last value.
	**/
	public function new(preset:Int, target:Int, slot:Int, loop:Int) {
		this.preset = preset;
		this.target = target;
		this.slot = slot;
		this.loop = loop;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		final line = laneOf(song);
		if (line == null) return;

		was = line.loop;
		line.loop = loop < 0 || loop >= line.points.length ? -1 : loop;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		final line = laneOf(song);
		if (line != null) line.loop = was;
	}

	function laneOf(song:Song):Null<Automation> {
		final instrument = song.instrumentAt(preset);
		return instrument == null ? null : instrument.lane(target, slot);
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "loop a lane";
	}
}
