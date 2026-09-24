package mdd.song.edit;

/**
	Measures a lane a preset carries in milliseconds or in beats, moving every point so it stays
	where it sat at a tempo, which is the one the song opens at.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class TimeLane implements Command {
	final preset:Int;
	final target:Int;
	final slot:Int;
	final synced:Bool;
	final beats:Float;
	final was:Array<Int> = [];

	var wasSynced:Bool = false;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param preset Which instrument, by index.
		@param target Which parameter the lane moves.
		@param slot Which operator, for a per operator one.
		@param synced Whether it is to follow the tempo.
		@param beats The tempo its points keep their places at, in beats a minute.
	**/
	public function new(preset:Int, target:Int, slot:Int, synced:Bool, beats:Float) {
		this.preset = preset;
		this.target = target;
		this.slot = slot;
		this.synced = synced;
		this.beats = beats <= 0 ? 120 : beats;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		final line = laneOf(song);
		if (line == null) return;

		wasSynced = line.synced;
		was.resize(0);

		for (point in line.points) was.push(point.at);

		if (line.synced == synced) return;

		final unit = 60000 / (beats * Automation.BEAT);

		for (point in line.points) {
			point.at = synced ? Math.round(point.at / unit) : Math.round(point.at * unit);
		}

		line.synced = synced;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		final line = laneOf(song);
		if (line == null) return;

		for (index in 0...line.points.length) {
			if (index < was.length) line.points[index].at = was[index];
		}

		line.synced = wasSynced;
	}

	function laneOf(song:Song):Null<Automation> {
		final instrument = song.instrumentAt(preset);
		return instrument == null ? null : instrument.lane(target, slot);
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "time a lane";
	}
}
