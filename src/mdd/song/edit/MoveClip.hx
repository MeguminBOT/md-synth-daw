package mdd.song.edit;

/**
	Moves a clip along its track, to another track, or transposes it.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class MoveClip implements Command {
	final track:Int;
	final onto:Int;
	final clip:Clip;
	final at:Int;
	final transpose:Int;

	var wasAt:Int = 0;
	var wasTranspose:Int = 0;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param track Which track, by index.
		@param clip The clip.
		@param at Which one, by index.
		@param transpose Semitones to shift the clip notes by.
		@param onto The track to move it to, or -1 to leave it where it is.
	**/
	public function new(track:Int, clip:Clip, at:Int, transpose:Int, onto:Int = -1) {
		this.track = track;
		this.onto = onto < 0 ? track : onto;
		this.clip = clip;
		this.at = at;
		this.transpose = transpose;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		wasAt = clip.at;
		wasTranspose = clip.transpose;

		clip.at = at < 0 ? 0 : at;
		clip.transpose = transpose;

		carries(song, track, onto);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		clip.at = wasAt;
		clip.transpose = wasTranspose;

		carries(song, onto, track);
	}

	function carries(song:Song, from:Int, to:Int):Void {
		if (from == to) return;
		if (from < 0 || from >= song.tracks.length) return;
		if (to < 0 || to >= song.tracks.length) return;

		song.tracks[from].remove(clip);
		song.tracks[to].add(clip);
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "move a clip";
	}
}
