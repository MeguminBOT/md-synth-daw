package mdd.song.edit;

/**
	Changes the grid the editors snap to.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class SetGrid implements Command {
	final beats:Float;

	var was:Float = 0;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param beats The new value, in beats.
	**/
	public function new(beats:Float) {
		this.beats = beats;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		was = song.tempo.beatsAt(0);
		song.regrid(beats);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		if (was > 0) song.regrid(was);
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "move the grid";
	}
}
