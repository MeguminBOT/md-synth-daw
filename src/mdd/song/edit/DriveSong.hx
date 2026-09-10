package mdd.song.edit;

/**
	Paces the piece the way a sound driver on the machine would, or stops doing that.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class DriveSong implements Command {
	final driving:Bool;

	var was:Bool = false;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param driving Whether every frame is held to the writes a driver could make.
	**/
	public function new(driving:Bool) {
		this.driving = driving;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		was = song.driving;
		song.driving = driving;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		song.driving = was;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return driving ? "play through a driver" : "stop playing through a driver";
	}
}
