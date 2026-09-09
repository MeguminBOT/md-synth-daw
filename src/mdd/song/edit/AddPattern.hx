package mdd.song.edit;

/**
	Adds a pattern to the song.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class AddPattern implements Command {
	final pattern:Pattern;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param pattern Which pattern, by index.
	**/
	public function new(pattern:Pattern) {
		this.pattern = pattern;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		song.patterns.push(pattern);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		song.patterns.remove(pattern);
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "add a pattern";
	}
}
