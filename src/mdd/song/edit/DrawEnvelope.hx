package mdd.song.edit;

/**
	Replaces a square envelope's steps with the ones a stroke drew.

	A stroke crosses many steps, so it is one command holding the whole list rather
	than one command per step, and undo takes the stroke back rather than unpicking it.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class DrawEnvelope implements Command {
	final envelope:Envelope;
	final steps:Array<Int>;

	final was:Array<Int> = [];

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param envelope The envelope being drawn on.
		@param steps The attenuation at each step, which is copied rather than held.
	**/
	public function new(envelope:Envelope, steps:Array<Int>) {
		this.envelope = envelope;
		this.steps = steps.copy();
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		was.resize(0);
		for (value in envelope.steps) was.push(value);

		fills(steps);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		fills(was);
	}

	/**
		@param from The list to take.
	**/
	function fills(from:Array<Int>):Void {
		envelope.steps.resize(0);
		for (value in from) envelope.steps.push(value);
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "draw an envelope";
	}
}
