package mdd.song.edit;

/**
	Moves a track to another row.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class MoveTrack implements Command {
	final at:Int;
	final onto:Int;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param at Which one, by index.
		@param onto The track to move it to, or -1 to leave it where it is.
	**/
	public function new(at:Int, onto:Int) {
		this.at = at;
		this.onto = onto;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		carries(song, at, onto);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		carries(song, onto, at);
	}

	static function carries(song:Song, from:Int, to:Int):Void {
		final tracks = song.tracks;

		if (from == to) return;
		if (from < 0 || from >= tracks.length) return;
		if (to < 0 || to >= tracks.length) return;

		final held = tracks[from];

		tracks.splice(from, 1);
		tracks.insert(to, held);
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "move a track";
	}
}
