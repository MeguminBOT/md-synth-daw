package mdd.song.edit;

/**
	Copies a track and everything on it, and puts the copy after it.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class CloneTrack implements Command {
	final at:Int;

	var made:Int = -1;

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

		final from = song.tracks[at];
		final held = new Track(from.name);

		held.colour = from.colour;
		held.icon = from.icon;
		held.muted = from.muted;

		for (clip in from.clips) held.add(clip.copy());

		made = at + 1;
		song.tracks.insert(made, held);
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
		return "clone a track";
	}
}
