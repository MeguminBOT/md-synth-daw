package mdd.song.edit;

/**
	Ties a note to the one before it, or unties it. A tied note changes the pitch of the note it
	follows without a new key on, and the note before it is not keyed off, which is how a driver
	plays a legato line on one channel.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class TieNote implements Command {
	final note:Note;
	final tied:Bool;

	var was:Bool = false;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param note The note.
		@param tied Whether it runs on from the note before it.
	**/
	public function new(note:Note, tied:Bool) {
		this.note = note;
		this.tied = tied;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		was = note.tied;
		note.tied = tied;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		note.tied = was;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return tied ? "tie a note" : "untie a note";
	}
}
