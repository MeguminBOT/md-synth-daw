package mdd.song.edit;

/**
	Takes a clip off a track.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class RemoveClip implements Command {
	final track:Int;
	final clip:Clip;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param track Which track, by index.
		@param clip The clip.
	**/
	public function new(track:Int, clip:Clip) {
		this.track = track;
		this.clip = clip;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		if (track >= 0 && track < song.tracks.length) song.tracks[track].remove(clip);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		if (track >= 0 && track < song.tracks.length) song.tracks[track].add(clip);
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "remove a clip";
	}
}
