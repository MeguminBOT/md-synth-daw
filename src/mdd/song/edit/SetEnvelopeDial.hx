package mdd.song.edit;

/**
	Changes one of a square envelope's settings: where it loops, how fast it runs, or
	which noise goes with it.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class SetEnvelopeDial implements Command {
	final envelope:Envelope;
	final which:Int;
	final value:Int;

	var was:Int = 0;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param envelope The envelope being edited.
		@param which Which dial.
		@param value What to turn it to. The envelope holds it to what that dial takes.
	**/
	public function new(envelope:Envelope, which:Int, value:Int) {
		this.envelope = envelope;
		this.which = which;
		this.value = value;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		was = envelope.dial(which);
		envelope.turns(which, value);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		envelope.turns(which, was);
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "turn an envelope dial";
	}
}
