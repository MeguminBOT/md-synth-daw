package mdd.song.edit;

/**
	Renames a pattern.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class RenamePattern implements Command {
	final which:Int;
	final name:String;

	var was:String = "";

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param which Which one, by index.
		@param name The new name.
	**/
	public function new(which:Int, name:String) {
		this.which = which;
		this.name = name;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		final pattern = song.patternAt(which);
		if (pattern == null) return;

		was = pattern.name;
		pattern.name = name;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		final pattern = song.patternAt(which);
		if (pattern != null) pattern.name = was;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "rename a pattern";
	}
}
