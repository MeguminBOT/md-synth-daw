package mdd.song.edit;

/**
	Changes one field of one operator on a patch.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class SetOperator implements Command {
	final patch:Patch;
	final slot:Int;
	final row:Int;
	final value:Int;

	var was:Int = 0;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param patch The patch being edited.
		@param slot Which operator, 0 to 3.
		@param row Which field of it.
		@param value What to set it to. The patch holds it to what the register takes.
	**/
	public function new(patch:Patch, slot:Int, row:Int, value:Int) {
		this.patch = patch;
		this.slot = slot;
		this.row = row;
		this.value = value;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		was = patch.reads(slot, row);
		patch.writes(slot, row, value);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		patch.writes(slot, row, was);
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "set an operator";
	}
}
