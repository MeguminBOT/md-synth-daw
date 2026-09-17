package mdd.song.edit;

/**
	Changes one of the descriptions a piece carries: its title, artist, composer, album, year,
	genre, track number or comment.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class DescribeSong implements Command {
	final which:Int;
	final value:String;

	var was:String = "";

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param which Which description, from `Song.TITLE` to `Song.COMMENT`.
		@param value What it holds now.
	**/
	public function new(which:Int, value:String) {
		this.which = which;
		this.value = value;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		was = song.described(which);
		song.describes(which, value);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		song.describes(which, was);
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "describe the piece";
	}
}
