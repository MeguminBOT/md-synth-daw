package mdd.song.edit;

/**
	Changes how hard a note is played.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class SetVelocity implements Command {
	final note:Note;
	final velocity:Int;

	var was:Int = 0;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param note The note.
		@param velocity The new velocity, 0 to 127.
	**/
	public function new(note:Note, velocity:Int) {
		this.note = note;
		this.velocity = velocity < 1 ? 1 : (velocity > 127 ? 127 : velocity);
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		was = note.velocity;
		note.velocity = velocity;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		note.velocity = was;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "set a velocity";
	}
}
