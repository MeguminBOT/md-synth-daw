package mdd.song.edit;

/**
	Solos or unsolos a track.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class SoloTrack implements Command {
	final at:Int;
	final soloed:Bool;

	var was:Bool = false;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param at Which one, by index.
		@param soloed Whether the track is soloed.
	**/
	public function new(at:Int, soloed:Bool) {
		this.at = at;
		this.soloed = soloed;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		was = song.tracks[at].soloed;
		song.tracks[at].soloed = soloed;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		song.tracks[at].soloed = was;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return soloed ? "solo a track" : "unsolo a track";
	}
}
