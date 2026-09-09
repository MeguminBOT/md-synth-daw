package mdd.song.edit;

/**
	Changes how long a pattern is.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class ResizePattern implements Command {
	final which:Int;
	final length:Int;

	var was:Int = 0;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param which Which one, by index.
		@param length The new length, in ticks.
	**/
	public function new(which:Int, length:Int) {
		this.which = which;
		this.length = length < 1 ? 1 : length;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		final pattern = song.patternAt(which);
		if (pattern == null) return;

		was = pattern.length;
		pattern.length = length;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		final pattern = song.patternAt(which);
		if (pattern != null) pattern.length = was;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "resize a pattern";
	}
}
