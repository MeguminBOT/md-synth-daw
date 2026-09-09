package mdd.song.edit;

/**
	Takes a note out of a lane.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class RemoveNote implements Command {
	final pattern:Int;
	final part:Part;
	final note:Note;

	var wasLength:Int = 0;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param pattern Which pattern, by index.
		@param part Which part of the pattern.
		@param note The note.
	**/
	public function new(pattern:Int, part:Part, note:Note) {
		this.pattern = pattern;
		this.part = part;
		this.note = note;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		final held = song.patternAt(pattern);
		if (held == null) return;

		held.lane(part).remove(note);
		wasLength = held.fits(song.tempo.ppqn * 4);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		final held = song.patternAt(pattern);
		if (held == null) return;

		held.lane(part).add(note);
		held.length = wasLength;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "remove a note";
	}
}
