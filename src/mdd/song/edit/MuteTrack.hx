package mdd.song.edit;

/**
	Mutes or unmutes a track.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class MuteTrack implements Command {
	final at:Int;
	final muted:Bool;

	var was:Bool = false;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param at Which one, by index.
		@param muted Whether the track is muted.
	**/
	public function new(at:Int, muted:Bool) {
		this.at = at;
		this.muted = muted;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		was = song.tracks[at].muted;
		song.tracks[at].muted = muted;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		song.tracks[at].muted = was;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return muted ? "mute a track" : "unmute a track";
	}
}
