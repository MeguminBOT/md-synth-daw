package mdd.song.edit;

/**
	Changes register `$27` as the song holds it, which is what switches channel three between one
	note on all four operators and a note on each.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class SetMode implements Command {
	final value:Int;

	var was:Int = 0;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param value The whole register byte.
	**/
	public function new(value:Int) {
		this.value = value & 0xFF;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		was = song.mode;
		song.mode = value;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		song.mode = was;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "switch channel three's mode";
	}
}
