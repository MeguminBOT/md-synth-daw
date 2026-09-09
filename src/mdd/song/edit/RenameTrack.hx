package mdd.song.edit;

/**
	Renames a track.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class RenameTrack implements Command {
	final at:Int;
	final name:String;

	var was:String = "";

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
		if (at < 0 || at >= song.tracks.length) return;

		was = song.tracks[at].name;
		song.tracks[at].name = name;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		song.tracks[at].name = was;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "rename a track";
	}
}
