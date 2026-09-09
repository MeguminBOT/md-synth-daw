package mdd.song.edit;

/**
	Puts a new empty track at a position, moving the rest down.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class InsertTrack implements Command {
	final at:Int;
	final name:String;

	var made:Int = -1;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param at Which one, by index.
		@param name The new name.
	**/
	public function new(at:Int, name:String) {
		this.at = at;
		this.name = name;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		if (at < 0 || at > song.tracks.length) return;

		made = at;
		song.tracks.insert(made, new Track(name));
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		if (made < 0 || made >= song.tracks.length) return;

		song.tracks.splice(made, 1);
		made = -1;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "insert a track";
	}
}
