package mdd.song.edit;

/**
	Removes a track and everything on it.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class RemoveTrack implements Command {
	final at:Int;

	var held:Null<Track> = null;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param at Which one, by index.
	**/
	public function new(at:Int) {
		this.at = at;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		held = song.tracks[at];
		song.tracks.splice(at, 1);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		final track = held;
		if (track == null || at < 0 || at > song.tracks.length) return;

		song.tracks.insert(at, track);
		held = null;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "remove a track";
	}
}
