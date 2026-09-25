package mdd.song.edit;

/**
	Changes how long a note is.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class SizeNote implements Command {
	final pattern:Int;
	final part:Part;
	final note:Note;
	final length:Int;

	var was:Int = 0;
	var wasLength:Int = 0;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param pattern Which pattern, by index.
		@param part Which part of the pattern.
		@param note The note.
		@param length The new length, in ticks.
	**/
	public function new(pattern:Int, part:Part, note:Note, length:Int) {
		this.pattern = pattern;
		this.part = part;
		this.note = note;
		this.length = length;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		was = note.length;
		note.length = length < 1 ? 1 : length;

		final held = song.patternAt(pattern);
		if (held == null) return;

		held.lane(part).grow(note.length);
		wasLength = held.fits(song.barOf(held));
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		note.length = was;

		final held = song.patternAt(pattern);
		if (held == null) return;

		held.lane(part).grow(note.length);
		held.length = wasLength;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "resize a note";
	}
}
