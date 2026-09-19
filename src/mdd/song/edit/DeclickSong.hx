package mdd.song.edit;

/**
	Smooths the edges the parts would otherwise click on, or stops doing that.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class DeclickSong implements Command {
	final declick:Bool;

	var was:Bool = false;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param declick Whether the sequencer smooths the edges the parts would click on.
	**/
	public function new(declick:Bool) {
		this.declick = declick;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		was = song.declick;
		song.declick = declick;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		song.declick = was;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return declick ? "declick" : "stop declicking";
	}
}
