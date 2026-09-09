package mdd.song.edit;

/**
	Changes the tempo at a point in the map.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class SetTempo implements Command {
	final at:Int;
	final beats:Float;

	var was:Float = 0;
	var existed:Bool = false;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param at Which one, by index.
		@param beats The new value, in beats.
	**/
	public function new(at:Int, beats:Float) {
		this.at = at;
		this.beats = beats;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		existed = false;

		for (i in 0...song.tempo.at.length) {
			if (song.tempo.at[i] != at) continue;
			existed = true;
			was = song.tempo.bpm[i];
		}

		song.tempo.set(at, beats);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		if (existed) song.tempo.set(at, was);
		else song.tempo.drop(at);
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "set the tempo";
	}
}
