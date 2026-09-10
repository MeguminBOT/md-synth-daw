package mdd.song.edit;

/**
	Turns the converter into a drum kit, or back into an ordinary channel.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class KitDrums implements Command {
	final drums:Bool;

	var was:Bool = false;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param drums Whether a note's pitch picks the sample.
	**/
	public function new(drums:Bool) {
		this.drums = drums;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		was = song.drums;
		song.drums = drums;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		song.drums = was;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "switch the converter";
	}
}
