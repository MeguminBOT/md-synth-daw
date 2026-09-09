package mdd.song.edit;

/**
	One undoable step.

	Every edit in the application is one of these, which is what makes undo cover
	everything rather than the parts somebody remembered. A command records what to do
	when it is built, does it in `apply`, and puts the song back exactly as it was in
	`revert`, so it keeps whatever it is about to overwrite.
**/
interface Command {
	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void;

	/**
		Puts the song back as it was. Only ever called after `apply`.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void;

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String;
}
