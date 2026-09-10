package mdd.song.edit;

/**
	Changes one of a patch's channel wide values: the algorithm, the feedback, or how
	far the LFO reaches the amplitude and the pitch.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class SetDial implements Command {
	final patch:Patch;
	final which:Int;
	final value:Int;

	var was:Int = 0;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param patch The patch being edited.
		@param which Which dial.
		@param value What to turn it to. The patch holds it to what the register takes.
	**/
	public function new(patch:Patch, which:Int, value:Int) {
		this.patch = patch;
		this.which = which;
		this.value = value;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		was = patch.dial(which);
		patch.turns(which, value);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		patch.turns(which, was);
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "turn a dial";
	}
}
