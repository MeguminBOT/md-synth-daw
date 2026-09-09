package mdd.song.edit;

/**
	Cuts a clip in two at a tick.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class SliceClip implements Command {
	final track:Int;
	final clip:Clip;
	final at:Int;

	var rest:Null<Clip> = null;
	var was:Int = 0;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param track Which track, by index.
		@param clip The clip.
		@param at Which one, by index.
	**/
	public function new(track:Int, clip:Clip, at:Int) {
		this.track = track;
		this.clip = clip;
		this.at = at;
	}

	public static function splits(clip:Clip, at:Int):Bool {
		return !clip.drawn() && at > clip.at && at < clip.ends();
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		if (track < 0 || track >= song.tracks.length) return;
		if (!splits(clip, at)) return;

		was = clip.length;

		var made = rest;

		if (made == null) {
			made = new Clip(clip.pattern, at, was - (at - clip.at), clip.transpose,
				clip.offset + (at - clip.at));
			rest = made;
		}

		clip.length = at - clip.at;
		song.tracks[track].add(made);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		final made = rest;
		if (made == null) return;

		if (track >= 0 && track < song.tracks.length) song.tracks[track].remove(made);
		clip.length = was;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "slice a clip";
	}
}
