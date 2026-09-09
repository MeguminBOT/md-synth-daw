package mdd.song.edit;

/**
	Recolours a pattern, which is what its clips draw from.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class ColourPattern implements Command {
	final which:Int;
	final colour:Int;

	var was:Int = -1;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param which Which one, by index.
		@param colour The colour, packed as the theme packs one.
	**/
	public function new(which:Int, colour:Int) {
		this.which = which;
		this.colour = colour;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		final pattern = song.patternAt(which);
		if (pattern == null) return;

		was = pattern.colour;
		pattern.colour = colour;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		final pattern = song.patternAt(which);
		if (pattern != null) pattern.colour = was;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "colour a pattern";
	}
}
